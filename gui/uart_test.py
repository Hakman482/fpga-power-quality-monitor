import serial
import time

PORT = "COM3"       # CHANGE THIS
BAUD = 115200

ser = serial.Serial(PORT, BAUD, timeout=1)

print(f"Opened {PORT} at {BAUD} baud")
print("Waiting for FPGA data...\n")

while True:
    data = ser.read(100)

    if data:
        print(f"{len(data)} bytes:", data.hex(" "))
    else:
        print("NO DATA")

    time.sleep(0.2)