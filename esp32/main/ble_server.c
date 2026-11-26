/* Anuncia HealthBand y fragmenta líneas HB1 dentro de una única conexión NimBLE. */
#include "ble_server.h"
#include "hb1_framing.h"

#include <inttypes.h>
#include <stdlib.h>
#include <string.h>

#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "host/ble_att.h"
#include "host/ble_gap.h"
#include "host/ble_gatt.h"
#include "host/ble_hs.h"
#include "host/util/util.h"

#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"

static const char *TAG = "healthband_ble";
static ble_uuid128_t service_uuid = BLE_UUID128_INIT(
    0x9e, 0xca, 0xdc, 0x24, 0x0e, 0xe5, 0xa9, 0xe0, 0x93, 0xf3, 0xa3, 0xb5, 0x01, 0x00, 0x40, 0x6e);
static const ble_uuid128_t notify_uuid = BLE_UUID128_INIT(
    0x9e, 0xca, 0xdc, 0x24, 0x0e, 0xe5, 0xa9, 0xe0, 0x93, 0xf3, 0xa3, 0xb5, 0x03, 0x00, 0x40, 0x6e);

static portMUX_TYPE lock = portMUX_INITIALIZER_UNLOCKED;
static hb_mailbox mailbox;
static struct ble_npl_callout send_timer;
static struct ble_npl_callout advertise_retry;
static uint8_t address_type;
static uint16_t connection = BLE_HS_CONN_HANDLE_NONE;
static uint16_t notify_handle;
static const char *device_name;
static size_t fragment_cap;
static uint32_t submitted, failures;
static bool closing, notify_enabled;

static void set_subscription(bool enabled)
{
    notify_enabled = enabled;
    portENTER_CRITICAL(&lock);
    hb_link(&mailbox, enabled);
    portEXIT_CRITICAL(&lock);
}

uint32_t bridge_ble_generation(void)
{
    portENTER_CRITICAL(&lock);
    uint32_t generation = mailbox.generation;
    portEXIT_CRITICAL(&lock);
    return generation;
}

bool bridge_ble_submit(uint32_t generation, const uint8_t *data, size_t length)
{
    portENTER_CRITICAL(&lock);
    bool queued = hb_publish(&mailbox, generation, data, length);
    portEXIT_CRITICAL(&lock);
    return queued;
}

static void close_link(void)
{
    int rc = ble_gap_terminate(connection, BLE_ERR_REM_USER_CONN_TERM);
    if (rc && rc != BLE_HS_EALREADY && rc != BLE_HS_ENOTCONN) {
        ESP_LOGW(TAG, "Terminate rc=%d; se reintenta sin enviar datos", rc);
        ble_npl_callout_reset(&send_timer, ble_npl_time_ms_to_ticks32(1000));
    }
}

static bool notify_frame(const uint8_t *frame, size_t length)
{
    for (size_t offset = 0; offset < length;) {
        size_t count = hb_fragment_size(length - offset, ble_att_mtu(connection), fragment_cap);
        struct os_mbuf *packet = ble_hs_mbuf_from_flat(frame + offset, count);
        // NimBLE consume el mbuf incluso cuando falla. Notify carece de ACK del cliente.
        int rc = packet ? ble_gatts_notify_custom(connection, notify_handle, packet) : BLE_HS_ENOMEM;
        if (rc) {
            closing = true;
            set_subscription(false);
            ESP_LOGW(TAG, "Notify rc=%d offset=%zu fallos=%" PRIu32, rc, offset, ++failures);
            close_link();
            return false;
        }
        offset += count;
    }
    if (++submitted == 1 || submitted % 100 == 0) {
        ESP_LOGI(TAG, "Tramas aceptadas por la pila=%" PRIu32, submitted);
    }
    return true;
}

static void send_frame(struct ble_npl_event *event)
{
    (void)event;
    if (connection == BLE_HS_CONN_HANDLE_NONE) return;
    if (closing) {
        close_link();
        return;
    }
    if (!notify_enabled) return;
    uint8_t frame[HB_FRAME_CAPACITY];
    // El temporizador solo está activo con CCCD habilitado o durante un cierre en reintento.
    for (size_t i = 0; i < HB_QUEUE_CAPACITY; i++) {
        portENTER_CRITICAL(&lock);
        size_t length = hb_take(&mailbox, frame);
        portEXIT_CRITICAL(&lock);
        if (!length) break;
        if (!notify_frame(frame, length)) return;
    }
    ble_npl_callout_reset(&send_timer, ble_npl_time_ms_to_ticks32(50));
}

static int gap_event(struct ble_gap_event *event, void *arg);

static void advertise(struct ble_npl_event *event)
{
    (void)event;
    if (connection != BLE_HS_CONN_HANDLE_NONE) return;
    struct ble_hs_adv_fields fields = {
        .flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP,
        .uuids128 = &service_uuid,
        .num_uuids128 = 1,
        .uuids128_is_complete = 1
    };
    struct ble_hs_adv_fields response = {
        .name = (const uint8_t *)device_name,
        .name_len = strlen(device_name),
        .name_is_complete = 1
    };
    struct ble_gap_adv_params parameters = {
        .conn_mode = BLE_GAP_CONN_MODE_UND,
        .disc_mode = BLE_GAP_DISC_MODE_GEN
    };
    int rc = ble_gap_adv_set_fields(&fields);
    if (!rc) rc = ble_gap_adv_rsp_set_fields(&response);
    if (!rc) rc = ble_gap_adv_start(address_type, NULL, BLE_HS_FOREVER, &parameters, gap_event, NULL);
    if (rc && rc != BLE_HS_EALREADY) {
        ESP_LOGW(TAG, "Advertising rc=%d", rc);
        ble_npl_callout_reset(&advertise_retry, ble_npl_time_ms_to_ticks32(1000));
    } else {
        ESP_LOGI(TAG, "Advertising %s", device_name);
    }
}

static void restart_advertising(void)
{
    // Se sale del callback GAP antes de volver a iniciar advertising.
    ble_npl_callout_reset(&advertise_retry, 1);
}

static int gap_event(struct ble_gap_event *event, void *arg)
{
    (void)arg;
    switch (event->type) {
    case BLE_GAP_EVENT_CONNECT:
        if (event->connect.status == 0) {
            connection = event->connect.conn_handle;
            closing = false;
            ESP_LOGI(TAG, "Conexión %u", connection);
        } else {
            ESP_LOGW(TAG, "Conexión fallida rc=%d", event->connect.status);
            restart_advertising();
        }
        break;
    case BLE_GAP_EVENT_DISCONNECT:
        set_subscription(false);
        ble_npl_callout_stop(&send_timer);
        connection = BLE_HS_CONN_HANDLE_NONE;
        ESP_LOGI(TAG, "Desconexión motivo=%d", event->disconnect.reason);
        restart_advertising();
        break;
    case BLE_GAP_EVENT_ADV_COMPLETE:
        restart_advertising();
        break;
    case BLE_GAP_EVENT_SUBSCRIBE:
        if (!closing && event->subscribe.conn_handle == connection &&
            event->subscribe.attr_handle == notify_handle &&
            event->subscribe.prev_notify != event->subscribe.cur_notify) {
            set_subscription(event->subscribe.cur_notify);
            ESP_LOGI(TAG, "Suscripción Notify=%u", event->subscribe.cur_notify);
            // Tras desactivar CCCD se requiere una conexión nueva para vaciar el parser remoto.
            if (!event->subscribe.cur_notify) {
                closing = true;
                ble_npl_callout_stop(&send_timer);
                close_link();
            } else {
                ble_npl_callout_reset(&send_timer, 1);
            }
        }
        break;
    case BLE_GAP_EVENT_MTU:
        ESP_LOGI(TAG, "MTU=%u", event->mtu.value);
        break;
    default:
        break;
    }
    return 0;
}

static int notify_access(uint16_t conn, uint16_t attr, struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    (void)conn;
    (void)attr;
    (void)ctxt;
    (void)arg;
    return BLE_ATT_ERR_READ_NOT_PERMITTED;
}

static const struct ble_gatt_chr_def characteristics[] = {
    {.uuid = &notify_uuid.u, .flags = BLE_GATT_CHR_F_NOTIFY, .val_handle = &notify_handle,
     .access_cb = notify_access},
    {0}
};

static const struct ble_gatt_svc_def services[] = {
    {.type = BLE_GATT_SVC_TYPE_PRIMARY, .uuid = &service_uuid.u, .characteristics = characteristics},
    {0}
};

static void on_reset(int reason)
{
    set_subscription(false);
    connection = BLE_HS_CONN_HANDLE_NONE;
    ble_npl_callout_stop(&advertise_retry);
    ble_npl_callout_stop(&send_timer);
    ESP_LOGW(TAG, "Host reiniciado motivo=%d", reason);
}

static void on_sync(void)
{
    int rc = ble_hs_util_ensure_addr(0);
    if (!rc) rc = ble_hs_id_infer_auto(0, &address_type);
    if (rc) {
        ESP_LOGE(TAG, "Dirección BLE rc=%d", rc);
        return;
    }
    restart_advertising();
}

static void host_task(void *arg)
{
    (void)arg;
    nimble_port_run();
    nimble_port_freertos_deinit();
}

void bridge_ble_start(const char *name, size_t cap)
{
    device_name = name;
    fragment_cap = cap;
    ESP_ERROR_CHECK(nimble_port_init());
    ble_npl_callout_init(&send_timer, nimble_port_get_dflt_eventq(), send_frame, NULL);
    ble_npl_callout_init(&advertise_retry, nimble_port_get_dflt_eventq(), advertise, NULL);
    ble_hs_cfg.sync_cb = on_sync;
    ble_hs_cfg.reset_cb = on_reset;
    ble_svc_gap_init();
    ble_svc_gatt_init();
    int rc = ble_svc_gap_device_name_set(name);
    if (!rc) rc = ble_gatts_count_cfg(services);
    if (!rc) rc = ble_gatts_add_svcs(services);
    if (rc) {
        ESP_LOGE(TAG, "Configuración GATT rc=%d", rc);
        abort();
    }
    nimble_port_freertos_init(host_task);
}
