/* Prueba ensamblado, aislamiento de conexiones y fragmentación con bytes UART del RTL. */
#include "hb1_framing.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

static const char canonical[] = "HB1,SEQ=000012,BPM=075,IBI=0800,Q=1\n";

static unsigned feed(hb_framer *framer, const char *bytes, size_t length)
{
    unsigned count = 0;
    for (size_t i = 0; i < length; i++) {
        if (hb_feed(framer, (uint8_t)bytes[i]) == HB_COMPLETE) {
            count++;
            framer->length = 0;
        }
    }
    return count;
}

static void framing(void)
{
    assert(sizeof(canonical) - 1 == 36);
    hb_framer framer = {0};
    assert(feed(&framer, canonical, 20) == 0);
    assert(framer.length == 20);
    assert(feed(&framer, canonical + 20, strlen(canonical) - 20) == 1);
    assert(memcmp(canonical, framer.bytes, strlen(canonical)) == 0);
    char pair[80];
    int length = snprintf(pair, sizeof(pair), "%s%s", canonical, canonical);
    assert(feed(&framer, pair, length) == 2);

    for (size_t i = 0; i < HB_LINE_LIMIT; i++) assert(hb_feed(&framer, 'x') == HB_MORE);
    assert(hb_feed(&framer, 'x') == HB_DISCARDED);
    assert(feed(&framer, canonical, strlen(canonical)) == 0);
    assert(feed(&framer, canonical, strlen(canonical)) == 1);
    assert(feed(&framer, canonical, 7) == 0);
    hb_resync(&framer);
    assert(feed(&framer, "cola\n", 5) == 0);
    assert(feed(&framer, canonical, strlen(canonical)) == 1);
    assert(feed(&framer, "x\r\n", 3) == 1);
    assert(memcmp(framer.bytes, "x\r\n", 3) == 0);
}

static void queue(void)
{
    hb_mailbox mailbox = {0};
    uint8_t frame[HB_FRAME_CAPACITY];
    uint8_t byte = 0;
    assert(!hb_publish(&mailbox, 0, &byte, 1));
    hb_link(&mailbox, true);
    uint32_t first_session = mailbox.generation;
    for (byte = 0; byte < HB_QUEUE_CAPACITY; byte++) {
        assert(hb_publish(&mailbox, first_session, &byte, 1));
    }
    assert(!hb_publish(&mailbox, first_session, &byte, 1));
    assert(hb_take(&mailbox, frame) == 1 && frame[0] == 0);
    assert(hb_publish(&mailbox, first_session, &byte, 1));
    for (byte = 1; byte <= HB_QUEUE_CAPACITY; byte++) {
        assert(hb_take(&mailbox, frame) == 1 && frame[0] == byte);
    }
    assert(hb_publish(&mailbox, first_session, &byte, 1));
    hb_link(&mailbox, false);
    assert(hb_take(&mailbox, frame) == 0);
    hb_link(&mailbox, true);
    assert(!hb_publish(&mailbox, first_session, &byte, 1));
    assert(hb_publish(&mailbox, mailbox.generation, &byte, 1));
    assert(hb_take(&mailbox, frame) == 1 && frame[0] == byte);
}

static void test_source(void)
{
    const unsigned scenarios[] = {0, 60, 75, 100, 120};
    const char *expected[] = {"000,IBI=0000,Q=0", "060,IBI=1000,Q=1", "075,IBI=0800,Q=1",
                              "100,IBI=0600,Q=1", "120,IBI=0500,Q=1"};
    char frame[HB_FRAME_CAPACITY];
    for (unsigned i = 0; i < 5; i++) {
        assert(hb_test_frame(frame, sizeof(frame), 1000000, scenarios[i]) == strlen(canonical));
        assert(strncmp(frame, "HB1,SEQ=000000,BPM=", 19) == 0);
        assert(strstr(frame, expected[i]) != NULL);
    }
    for (unsigned i = 0; i < 150; i++) {
        assert(hb_test_frame(frame, sizeof(frame), i, 75) == strlen(canonical));
        char sequence[7];
        snprintf(sequence, sizeof(sequence), "%06u", i);
        assert(memcmp(frame + 8, sequence, 6) == 0);
    }
    assert(hb_test_frame(frame, 2, 0, 75) == 0);
}

static void rtl_stream(FILE *input, FILE *output, uint16_t mtu, size_t cap)
{
    rewind(input);
    fprintf(output, "MTU %u CAP %zu\n", mtu, cap);
    hb_framer framer = {0};
    unsigned lines = 0;
    int byte;
    while ((byte = fgetc(input)) != EOF) {
        hb_result result = hb_feed(&framer, (uint8_t)byte);
        assert(result != HB_DISCARDED);
        if (result != HB_COMPLETE) continue;
        assert(framer.length == strlen(canonical));
        assert(framer.bytes[framer.length - 1] == '\n');
        for (size_t offset = 0; offset < framer.length;) {
            size_t bytes = hb_fragment_size(framer.length - offset, mtu, cap);
            assert(bytes && bytes <= mtu - 3u && (!cap || bytes <= cap));
            for (size_t i = 0; i < bytes; i++) fprintf(output, "%02x", framer.bytes[offset + i]);
            fputc('\n', output);
            offset += bytes;
        }
        framer.length = 0;
        lines++;
    }
    assert(!ferror(input) && !ferror(output));
    assert(lines == 100 && framer.length == 0);
}

int main(int argc, char **argv)
{
    assert(argc == 3);
    framing();
    queue();
    test_source();
    assert(hb_fragment_size(36, 23, 0) == 20);
    assert(hb_fragment_size(16, 23, 0) == 16);
    assert(hb_fragment_size(36, 39, 0) == 36);
    assert(hb_fragment_size(36, 247, 0) == 36);
    assert(hb_fragment_size(36, 23, 7) == 7);
    FILE *input = fopen(argv[1], "rb");
    FILE *output = fopen(argv[2], "w");
    assert(input && output);
    rtl_stream(input, output, 23, 0);
    rtl_stream(input, output, 39, 0);
    rtl_stream(input, output, 247, 7);
    fclose(input);
    assert(fclose(output) == 0);
    puts("PASS: framing, FIFO BLE, reconexión, fuente sintética y 100 tramas RTL en tres perfiles ATT");
    return 0;
}
