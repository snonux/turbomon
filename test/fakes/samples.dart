// Realistic captures of Android /proc and sysfs text, trimmed to what the
// parsers read. Values are from a Pixel-class arm64 phone.

const meminfoSample = '''MemTotal:        7799096 kB
MemFree:          182532 kB
MemAvailable:    2843520 kB
Buffers:            5228 kB
Cached:          2715660 kB
SwapCached:        30536 kB
Active:          2716392 kB
Inactive:        2364012 kB
Active(anon):    1386076 kB
Inactive(anon):   632948 kB
Active(file):    1330316 kB
Inactive(file):  1731064 kB
Unevictable:      151880 kB
Mlocked:          151524 kB
SwapTotal:       4194300 kB
SwapFree:        2560972 kB
Dirty:               820 kB
Writeback:             0 kB
AnonPages:       2510672 kB
Mapped:          1260280 kB
Shmem:             36120 kB
KReclaimable:     193400 kB
Slab:             496416 kB
SReclaimable:     149436 kB
SUnreclaim:       346980 kB
KernelStack:       84128 kB
PageTables:       160204 kB
CmaTotal:         221184 kB
''';

/// Two `/proc/stat` readings one interval apart. cpu7 is offline in the
/// second one (hot-unplugged big core).
const procStatBefore = '''cpu  1000 100 500 8000 200 50 50 0 0 0
cpu0 250 25 125 2000 50 10 10 0 0 0
cpu1 250 25 125 2000 50 10 10 0 0 0
cpu7 500 50 250 4000 100 30 30 0 0 0
intr 123456 0 0 0
ctxt 987654
btime 1700000000
processes 54321
procs_running 3
procs_blocked 0
softirq 1234 0 0 0
''';

const procStatAfter = '''cpu  1600 100 700 8400 200 50 50 0 0 0
cpu0 450 25 225 2100 50 10 10 0 0 0
cpu1 260 25 130 2185 50 10 10 0 0 0
intr 123999 0 0 0
ctxt 999999
''';

const diskstatsBefore = '''   7       0 loop0 25 0 400 4 0 0 0 0 0 8 4 0 0 0 0
 254       0 zram0 31000 0 248000 120 52000 0 416000 600 0 900 720 0 0 0 0
   8       0 sda 120000 3000 9600000 50000 80000 6000 6400000 70000 0 90000 120000 0 0 0 0
   8       1 sda1 50 0 400 10 0 0 0 0 0 10 10 0 0 0 0
   8      16 sdb 2000 0 16000 900 10 0 80 5 0 800 905 0 0 0 0
 179       0 mmcblk0 500 10 4000 200 100 5 800 50 0 220 250 0 0 0 0
 179       1 mmcblk0p1 400 10 3200 150 100 5 800 50 0 200 200 0 0 0 0
 253       0 dm-0 90000 0 7200000 40000 60000 0 4800000 60000 0 80000 100000 0 0 0 0
''';

const diskstatsAfter = '''   7       0 loop0 25 0 400 4 0 0 0 0 0 8 4 0 0 0 0
 254       0 zram0 31500 0 252000 120 52600 0 420800 600 0 900 720 0 0 0 0
   8       0 sda 120200 3000 9620480 50100 80100 6000 6420480 70100 0 90100 120200 0 0 0 0
   8       1 sda1 60 0 480 10 0 0 0 0 0 10 10 0 0 0 0
   8      16 sdb 2000 0 16000 900 10 0 80 5 0 800 905 0 0 0 0
 179       0 mmcblk0 500 10 4000 200 100 5 800 50 0 220 250 0 0 0 0
 179       1 mmcblk0p1 400 10 3200 150 100 5 800 50 0 200 200 0 0 0 0
 253       0 dm-0 90100 0 7210000 40000 60100 0 4810000 60000 0 80000 100000 0 0 0 0
''';

/// `cat /proc/[0-9]*/stat`: init, a kernel thread, a name with spaces and
/// one with parentheses inside the comm field.
String pidStatLine(int pid, String comm, String state, int utime, int stime, int rss) =>
    '$pid ($comm) $state 1 $pid 0 0 -1 4194560 5000 0 10 0 $utime $stime 0 0 20 0 '
    '12 0 300 12345678912 $rss 18446744073709551615 1 1 0 0 0 0 0 0 0 0 0 0 17 3 0 0 0 0 0';

final pidStatsSample = [
  pidStatLine(1, 'init', 'S', 120, 340, 1024),
  pidStatLine(212, 'kworker/u16:3', 'I', 0, 15, 0),
  pidStatLine(4321, 'Binder:4321_2', 'S', 50, 5, 2000),
  pidStatLine(5555, 'com.example (x)', 'R', 900, 100, 51200),
  pidStatLine(6666, 'HwBinder: 1)', 'S', 1, 2, 300),
].join('\n');

const psSample = '''PID   USER     NAME
1     root     init
212   root     [kworker/u16:3]
4321  system   system_server
5555  u0_a174  com.example.app
6666  u0_a12   com.android.phone with space
''';

const batteryStatsSample = '''
  Estimated power use (mAh):
    Capacity: 4614, Computed drain: 1290, actual drain: 1200-1384
    Global
    screen: 400 apps: 400 duration: 9h 21m 0s 140ms
    UID u0a174: 212.4 fg: 180.2 bg: 32.2 ( cpu=150.1 wifi=40.3 )
    UID 1000: 88.1 ( cpu=60.0 sensors=28.1 )
    UID u0a12: 5.67 ( cpu=5.67 )
    Uid u10a5: 1.5 ( cpu=1.5 )
    Uid u0a174: 7.6 ( cpu=7.6 )
  Per-app mobile ms per packet:
''';

const thermalSample = '''cpu-0-0-usr=41200
cpu-1-0-usr=48900
gpuss-0-usr=39500
battery=31
xo-therm=33600
pa-therm0=-5000
sdm-therm=999999
tsens_tz_sensor_bogus=-273000
'''
    'skin=';
