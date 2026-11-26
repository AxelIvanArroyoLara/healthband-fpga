/* Conserva los bytes de la línea UART y ofrece una fuente sintética para la prueba BLE. */
#include "hb1_framing.h"
#include <stdio.h>
#include <string.h>

void hb_resync(hb_framer *framer)
{
    framer->length = 0;
    framer->discard = true;
}

hb_result hb_feed(hb_framer *framer, uint8_t byte)
{
    if (byte == '\n') {
        if (framer->discard) {
            framer->discard = false;
            return HB_MORE;
        }
        framer->bytes[framer->length++] = byte;
        return HB_COMPLETE;
    }
    if (framer->discard) return HB_MORE;
    if (framer->length >= HB_LINE_LIMIT) {
        hb_resync(framer);
        return HB_DISCARDED;
    }
    framer->bytes[framer->length++] = byte;
    return HB_MORE;
}

size_t hb_fragment_size(size_t remaining, uint16_t mtu, size_t test_cap)
{
    size_t payload = mtu >= 23 ? mtu - 3u : 20u;
    if (test_cap && test_cap < payload) payload = test_cap;
    return remaining < payload ? remaining : payload;
}

size_t hb_test_frame(char *buffer, size_t capacity, unsigned sequence, unsigned bpm)
{
    if (bpm != 0 && (bpm < 30 || bpm > 240)) return 0;
    int length = snprintf(buffer, capacity, "HB1,SEQ=%06u,BPM=%03u,IBI=%04u,Q=%u\n",
                          sequence % 1000000u, bpm, bpm ? 60000u / bpm : 0, bpm ? 1u : 0u);
    return length > 0 && (size_t)length < capacity ? (size_t)length : 0;
}

void hb_link(hb_mailbox *mailbox, bool subscribed)
{
    mailbox->generation++;
    mailbox->subscribed = subscribed;
    mailbox->head = 0;
    mailbox->count = 0;
}

bool hb_publish(hb_mailbox *mailbox, uint32_t generation, const uint8_t *data, size_t length)
{
    if (!mailbox->subscribed || generation != mailbox->generation ||
        mailbox->count == HB_QUEUE_CAPACITY || !length || length > HB_FRAME_CAPACITY) return false;
    size_t index = (mailbox->head + mailbox->count) % HB_QUEUE_CAPACITY;
    memcpy(mailbox->frames[index], data, length);
    mailbox->lengths[index] = length;
    mailbox->count++;
    return true;
}

size_t hb_take(hb_mailbox *mailbox, uint8_t *data)
{
    if (!mailbox->count) return 0;
    size_t length = mailbox->lengths[mailbox->head];
    memcpy(data, mailbox->frames[mailbox->head], length);
    mailbox->head = (mailbox->head + 1) % HB_QUEUE_CAPACITY;
    mailbox->count--;
    return length;
}
