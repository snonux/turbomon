# TurboMon snapshot

> This is a system-monitoring report from an Android phone, made by TurboMon. Identify the likely causes of any problem it shows (battery drain, heat, slowness, network issues) and suggest fixes. The JSON block follows the schema `turbomon.snapshot/1`.

## Context

- Device: Google Pixel Test
- Android: 14 (API 34), kernel 6.1.0
- Access level: Shizuku (ADB shell)
- Snapshot taken: 2026-10-10 12:00:10
- Window: 2026-10-10 12:00:00 to 2026-10-10 12:00:10 (10 s)
- CPU figures are utilisation from /proc/stat.

## Findings

- CPU averaged 63 % over 10 s (peak 65 %).
- com.example.hog averaged 38 % CPU over 3 samples (peak 40 %).
- Battery draining 650 mA with screen off.
- Temperature peaked at 45.0 °C.
- Thermal status is moderate: the device is throttling.
- Only 512.0 MiB RAM available (6 %).
- Internal is 95 % full (5.0 GiB free).
- Wi-Fi signal is weak (-78 dBm).
- Alert: CPU load above 60 % at 12:00:08 (top process com.example.hog).

## Data

```json
{
  "schema": "turbomon.snapshot/1",
  "generatedAt": "2026-10-10T12:00:10.000",
  "window": {
    "start": "2026-10-10T12:00:00.000",
    "end": "2026-10-10T12:00:10.000"
  },
  "device": {
    "manufacturer": "Google",
    "model": "Pixel Test",
    "release": "14",
    "sdk": 34,
    "kernel": "6.1.0"
  },
  "access": "Shizuku (ADB shell)",
  "cpuIsFrequencyProxy": false,
  "current": {
    "cpu": {
      "totalPercent": 65.0,
      "corePercents": [
        60.0,
        70.0
      ],
      "frequencies": [],
      "coreCount": 2
    },
    "memory": {
      "totalBytes": 8589934592,
      "availableBytes": 536870912,
      "cachedBytes": null,
      "buffersBytes": null,
      "swapTotalBytes": null,
      "swapFreeBytes": null
    },
    "gpu": null,
    "battery": {
      "percent": 55.0,
      "status": "unknown",
      "charging": false,
      "plugged": null,
      "health": null,
      "temperatureC": null,
      "voltageMv": 3800,
      "currentMa": -650.0,
      "powerW": -2.47,
      "screenOn": false
    },
    "network": null,
    "thermal": {
      "status": "moderate",
      "headroom": null,
      "zones": [
        {
          "name": "cpu",
          "celsius": 45.0
        }
      ]
    },
    "diskIo": null
  },
  "series": {
    "cpu": {
      "unit": "%",
      "points": [
        [
          1791633600000,
          60.0
        ],
        [
          1791633602000,
          61.0
        ],
        [
          1791633604000,
          62.0
        ],
        [
          1791633606000,
          63.0
        ],
        [
          1791633608000,
          64.0
        ],
        [
          1791633610000,
          65.0
        ]
      ]
    },
    "ram": {
      "unit": "%",
      "points": [
        [
          1791633600000,
          70.0
        ],
        [
          1791633602000,
          70.0
        ],
        [
          1791633604000,
          70.0
        ],
        [
          1791633606000,
          70.0
        ],
        [
          1791633608000,
          70.0
        ],
        [
          1791633610000,
          70.0
        ]
      ]
    },
    "temperature": {
      "unit": "°C",
      "points": [
        [
          1791633600000,
          40.0
        ],
        [
          1791633602000,
          41.0
        ],
        [
          1791633604000,
          42.0
        ],
        [
          1791633606000,
          43.0
        ],
        [
          1791633608000,
          44.0
        ],
        [
          1791633610000,
          45.0
        ]
      ]
    }
  },
  "cores": [],
  "processes": {
    "top": [
      {
        "pid": 4242,
        "user": "u0_a99",
        "name": "com.example.hog",
        "cpuPercent": 36.0,
        "rssBytes": 209715200,
        "state": "R",
        "batteryMah": 12.5
      }
    ],
    "averages": [
      {
        "name": "com.example.hog",
        "avgCpu": 38.0,
        "peakCpu": 40.0,
        "samples": 3
      },
      {
        "name": "system_server",
        "avgCpu": 5.0,
        "peakCpu": 6.0,
        "samples": 3
      }
    ]
  },
  "storage": [
    {
      "label": "Internal",
      "totalBytes": 107374182400,
      "freeBytes": 5368709120,
      "removable": false
    }
  ],
  "wifi": {
    "link": {
      "ssid": "Home",
      "rssi": -78,
      "linkMbps": 72,
      "frequency": 2412
    },
    "networks": [
      {
        "ssid": "Home",
        "rssi": -78,
        "frequency": 2412,
        "channel": 1,
        "channelWidth": 20,
        "security": "WPA2"
      }
    ]
  },
  "bluetooth": {
    "nearby": [
      {
        "name": "Buds",
        "rssi": -60,
        "type": "unknown",
        "maker": "Samsung",
        "source": "le"
      }
    ],
    "paired": [
      {
        "name": "Car",
        "connected": true,
        "profiles": [
          "audio"
        ]
      }
    ]
  },
  "alerts": [
    {
      "metric": "cpu",
      "threshold": 60.0,
      "durationSeconds": 60,
      "value": 64.0,
      "time": "2026-10-10T12:00:08.000",
      "culprit": "com.example.hog"
    }
  ],
  "history": [],
  "findings": [
    "CPU averaged 63 % over 10 s (peak 65 %).",
    "com.example.hog averaged 38 % CPU over 3 samples (peak 40 %).",
    "Battery draining 650 mA with screen off.",
    "Temperature peaked at 45.0 °C.",
    "Thermal status is moderate: the device is throttling.",
    "Only 512.0 MiB RAM available (6 %).",
    "Internal is 95 % full (5.0 GiB free).",
    "Wi-Fi signal is weak (-78 dBm).",
    "Alert: CPU load above 60 % at 12:00:08 (top process com.example.hog)."
  ],
  "diagnostics": {
    "cpuinfo": "Load: 4.2 / 3.9 / 3.1\n"
  }
}
```
