/* Ensamblado UART y fragmentación ATT con memoria acotada. */
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

enum { HB_LINE_LIMIT = 128, HB_FRAME_CAPACITY = HB_LINE_LIMIT + 1 };
typedef struct {
    uint8_t bytes[HB_FRAME_CAPACITY];
    size_t length;
    bool discard;
} hb_framer;
typedef enum { HB_MORE, HB_COMPLETE, HB_DISCARDED } hb_result;

hb_result hb_feed(hb_framer *framer, uint8_t byte);
void hb_resync(hb_framer *framer);
size_t hb_fragment_size(size_t remaining, uint16_t mtu, size_t test_cap);
size_t hb_test_frame(char *buffer, size_t capacity, unsigned sequence, unsigned bpm);

/* Cola FIFO acotada. El llamador serializa su acceso entre UART y el host BLE. */
enum { HB_QUEUE_CAPACITY = 4 };
typedef struct {
    uint8_t frames[HB_QUEUE_CAPACITY][HB_FRAME_CAPACITY];
    size_t lengths[HB_QUEUE_CAPACITY];
    size_t head;
    size_t count;
    uint32_t generation;
    bool subscribed;
} hb_mailbox;

void hb_link(hb_mailbox *mailbox, bool subscribed);
bool hb_publish(hb_mailbox *mailbox, uint32_t generation, const uint8_t *data, size_t length);
size_t hb_take(hb_mailbox *mailbox, uint8_t *data);
