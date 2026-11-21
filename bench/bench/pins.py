"""Pinout notes for common boards (the gotchas that actually bite)."""
from __future__ import annotations

PINOUTS: dict[str, dict] = {
    "esp32": {
        "board": "ESP32-DevKitC (ESP32-WROOM-32)",
        "logic": "3.3V (NOT 5V tolerant)",
        "pins": {
            "GPIO0": "boot strap: LOW at reset = download mode; has pull-up",
            "GPIO2": "boot strap (must be LOW/floating to flash); onboard LED on many boards",
            "GPIO4": "safe GPIO, ADC2 (ADC2 unusable while WiFi is on)",
            "GPIO5": "boot strap (SDIO timing), VSPI CS; OK as output",
            "GPIO6-11": "DO NOT USE: wired to SPI flash",
            "GPIO12": "boot strap MTDI: HIGH at reset sets flash 1.8V -> boot fails",
            "GPIO13": "safe GPIO, HSPI MOSI",
            "GPIO14": "outputs PWM at boot",
            "GPIO15": "boot strap: outputs PWM at boot; LOW silences boot log",
            "GPIO16-17": "safe GPIO (not on WROVER: PSRAM)",
            "GPIO18": "safe, VSPI SCK", "GPIO19": "safe, VSPI MISO",
            "GPIO21": "I2C SDA (default)", "GPIO22": "I2C SCL (default)",
            "GPIO23": "safe, VSPI MOSI",
            "GPIO25-26": "DAC1/DAC2",
            "GPIO32-33": "safe GPIO, ADC1, touch",
            "GPIO34-39": "INPUT ONLY, no internal pull-up/down",
            "EN": "reset (active LOW)",
        },
        "power": "brownout at ~2.43V; WiFi TX peaks ~350mA: add 100-470uF near 3V3",
    },
    "rp2040": {
        "board": "Raspberry Pi Pico",
        "logic": "3.3V (NOT 5V tolerant)",
        "pins": {
            "GP0-1": "UART0 TX/RX (default)",
            "GP4-5": "I2C0 SDA/SCL (default)",
            "GP16-19": "SPI0",
            "GP25": "onboard LED (Pico; on Pico W the LED is on the WiFi chip)",
            "GP26-28": "ADC0-2",
            "VSYS": "1.8-5.5V input",
            "3V3_EN": "pull LOW to turn off 3.3V regulator",
            "RUN": "reset (active LOW)",
        },
        "power": "3V3 out max ~300mA total",
    },
    "avr": {
        "board": "Arduino Uno (ATmega328P)",
        "logic": "5V",
        "pins": {
            "D0-1": "USB serial RX/TX: avoid while uploading",
            "D3,5,6,9,10,11": "PWM",
            "D13": "onboard LED, SPI SCK",
            "A4-5": "I2C SDA/SCL",
        },
        "power": "40mA max per pin, 200mA total",
    },
}


def get(family: str) -> dict:
    if family not in PINOUTS:
        raise KeyError(f"no pinout for '{family}' (known: {', '.join(PINOUTS)})")
    return PINOUTS[family]
