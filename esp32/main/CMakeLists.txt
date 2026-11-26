# El framing se comparte con las pruebas nativas.
idf_component_register(SRCS "main.c" "ble_server.c" "hb1_framing.c"
    INCLUDE_DIRS "." PRIV_REQUIRES bt nvs_flash esp_driver_uart esp_driver_gpio)
