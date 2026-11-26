/* Servidor GATT y entrada de líneas desde la tarea productora. */
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

void bridge_ble_start(const char *name, size_t fragment_cap);
uint32_t bridge_ble_generation(void);
bool bridge_ble_submit(uint32_t generation, const uint8_t *data, size_t length);
