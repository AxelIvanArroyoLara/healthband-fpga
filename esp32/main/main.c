/* Selecciona una fuente exclusiva y entrega líneas completas al servidor BLE. */
#include "ble_server.h"
#include "hb1_framing.h"

#include <inttypes.h>
#include "driver/gpio.h"
#include "driver/uart.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"
#include "nvs_flash.h"
#include "sdkconfig.h"

static const char *TAG = "healthband";

#ifdef CONFIG_HB_TEST_MODE
static void run_test_source(void)
{
#if defined(CONFIG_HB_TEST_60)
    const unsigned bpm = 60;
#elif defined(CONFIG_HB_TEST_100)
    const unsigned bpm = 100;
#elif defined(CONFIG_HB_TEST_120)
    const unsigned bpm = 120;
#elif defined(CONFIG_HB_TEST_INVALID)
    const unsigned bpm = 0;
#else
    const unsigned bpm = 75;
#endif
#ifdef CONFIG_HB_TEST_FRAGMENT
    const size_t fragment_cap = 7;
#else
    const size_t fragment_cap = 0;
#endif
    ESP_LOGI(TAG, "Modo BLE_TEST sintético BPM=%u fragment_cap=%zu", bpm, fragment_cap);
    bridge_ble_start("HealthBand-Test", fragment_cap);
    TickType_t period = xTaskGetTickCount();
    unsigned sequence = 0;
    for (;;) {
        char frame[HB_FRAME_CAPACITY];
        size_t length = hb_test_frame(frame, sizeof(frame), sequence, bpm);
        bridge_ble_submit(bridge_ble_generation(), (const uint8_t *)frame, length);
        sequence = (sequence + 1) % 1000000u;
        vTaskDelayUntil(&period, pdMS_TO_TICKS(1000));
    }
}
#else
static void run_uart(void)
{
    const uart_port_t port = CONFIG_HB_UART_PORT;
    const int rx = CONFIG_HB_UART_RX;
    if (!GPIO_IS_VALID_GPIO(rx) || (rx >= 6 && rx <= 11) || rx == 1 || rx == 3) {
        ESP_LOGE(TAG, "GPIO RX incompatible con flash o consola: %d", rx);
        return;
    }
    const uart_config_t configuration = {
        .baud_rate = 115200, .data_bits = UART_DATA_8_BITS, .parity = UART_PARITY_DISABLE,
        .stop_bits = UART_STOP_BITS_1, .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
        .source_clk = UART_SCLK_DEFAULT
    };
    QueueHandle_t events = NULL;
    ESP_ERROR_CHECK(uart_param_config(port, &configuration));
    ESP_ERROR_CHECK(uart_set_pin(port, UART_PIN_NO_CHANGE, rx, UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE));
    ESP_ERROR_CHECK(uart_driver_install(port, 1024, 0, 32, &events, 0));
    ESP_LOGI(TAG, "Modo UART_BRIDGE UART%d RX=GPIO%d 115200 8N1", port, rx);
    bridge_ble_start("HealthBand", 0);
    hb_framer framer = {0};
    uint32_t generation = bridge_ble_generation();
    uint32_t received = 0, dropped = 0, errors = 0;
    for (;;) {
        uart_event_t event;
        if (!xQueueReceive(events, &event, portMAX_DELAY)) continue;
        switch (event.type) {
        case UART_DATA: {
            uint8_t bytes[64];
            size_t remaining = event.size;
            while (remaining) {
                size_t request = remaining < sizeof(bytes) ? remaining : sizeof(bytes);
                int length = uart_read_bytes(port, bytes, request, 0);
                if (length <= 0) {
                    hb_resync(&framer);
                    ESP_LOGW(TAG, "Lectura UART incompleta errores=%" PRIu32, ++errors);
                    break;
                }
                remaining -= length;
                for (int i = 0; i < length; i++) {
                    if (!framer.length && !framer.discard) generation = bridge_ble_generation();
                    hb_result result = hb_feed(&framer, bytes[i]);
                    if (result == HB_DISCARDED) {
                        ESP_LOGW(TAG, "Línea demasiado larga descartes=%" PRIu32, ++dropped);
                    } else if (result == HB_COMPLETE) {
                        received++;
                        if (!bridge_ble_submit(generation, framer.bytes, framer.length)) dropped++;
                        framer.length = 0;
                        if (received == 1 || received % 100 == 0) {
                            ESP_LOGI(TAG, "UART líneas=%" PRIu32 " descartes=%" PRIu32 " errores=%" PRIu32,
                                     received, dropped, errors);
                        }
                    }
                }
            }
            break;
        }
        case UART_FIFO_OVF:
        case UART_BUFFER_FULL:
        case UART_FRAME_ERR:
        case UART_PARITY_ERR:
        case UART_BREAK:
            xQueueReset(events);
            ESP_ERROR_CHECK(uart_flush_input(port));
            hb_resync(&framer);
            ESP_LOGW(TAG, "Evento UART %d errores=%" PRIu32, event.type, ++errors);
            break;
        default:
            break;
        }
    }
}
#endif

void app_main(void)
{
    ESP_LOGI(TAG, "Arranque HealthBand");
    esp_err_t rc = nvs_flash_init();
    if (rc == ESP_ERR_NVS_NO_FREE_PAGES || rc == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        rc = nvs_flash_init();
    }
    ESP_ERROR_CHECK(rc);
#ifdef CONFIG_HB_TEST_MODE
    run_test_source();
#else
    run_uart();
#endif
}
