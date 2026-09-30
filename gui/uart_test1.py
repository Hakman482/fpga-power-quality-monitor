import serial
import time

PORT = "COM10"      # change if Device Manager shows another COM port
BAUD = 115200

ser = serial.Serial(PORT, BAUD, timeout=1)

print(f"Opened {PORT} at {BAUD} baud")
print("Expected FPGA test byte: 0x55\n")

try:
    while True:
        data = ser.read(100)

        if data:
            print(f"{len(data)} bytes:", data.hex(" "))
        else:
            print("NO DATA")

        time.sleep(0.2)

except KeyboardInterrupt:
    print("\nStopped.")

finally:
    ser.close()
