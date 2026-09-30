library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity pq_nexys_top is

    port (
        CLK100MHZ  : in  std_logic;
        RESET      : in  std_logic;

        ADC_DOUT_V : in  std_logic;
        ADC_DOUT_I : in  std_logic;

        ADC_CS_N   : out std_logic;
        ADC_DCLOCK : out std_logic;

        UART_TX    : out std_logic
    );

end entity pq_nexys_top;


architecture rtl of pq_nexys_top is


    ------------------------------------------------------------------
    -- Raw acquisition signals
    ------------------------------------------------------------------

    signal voltage_raw :
        std_logic_vector(15 downto 0);

    signal current_raw :
        std_logic_vector(15 downto 0);


    ------------------------------------------------------------------
    -- Signed conditioned samples
    ------------------------------------------------------------------

    signal voltage_signed :
        signed(16 downto 0);

    signal current_signed :
        signed(16 downto 0);


    ------------------------------------------------------------------
    -- Instantaneous scaled engineering values
    ------------------------------------------------------------------

    signal voltage_mV :
        signed(31 downto 0);

    signal current_uA :
        signed(31 downto 0);


    ------------------------------------------------------------------
    -- RMS and frequency
    ------------------------------------------------------------------

    signal voltage_rms_mV :
        unsigned(31 downto 0);

    signal current_rms_uA :
        unsigned(31 downto 0);

    signal frequency_mHz :
        unsigned(31 downto 0);


    ------------------------------------------------------------------
    -- Power quantities
    ------------------------------------------------------------------

    signal active_power_mW :
        signed(31 downto 0);

    signal apparent_power_mVA :
        unsigned(31 downto 0);

    signal power_factor_milli :
        signed(15 downto 0);


    ------------------------------------------------------------------
    -- THD
    ------------------------------------------------------------------

    signal voltage_thd_x100 :
        unsigned(15 downto 0);

    signal current_thd_x100 :
        unsigned(15 downto 0);


    ------------------------------------------------------------------
    -- Valid strobes
    ------------------------------------------------------------------

    signal sample_valid :
        std_logic;

    signal rms_valid :
        std_logic;

    signal frequency_valid :
        std_logic;

    signal power_valid :
        std_logic;

    signal thd_valid :
        std_logic;


    ------------------------------------------------------------------
    -- UART byte interface
    ------------------------------------------------------------------

    signal uart_data :
        std_logic_vector(7 downto 0);

    signal uart_start :
        std_logic;

    signal uart_busy :
        std_logic;


    signal packet_busy :
        std_logic;


begin


    ------------------------------------------------------------------
    -- ACQUISITION + POWER QUALITY PIPELINE
    --
    -- TEST_MODE = true:
    --
    -- FPGA's internal test waveform is used.
    --
    -- TEST_MODE = false:
    --
    -- Samples come from the real PCB / ADC acquisition path.
    --
    -- FALSE is selected here for real PCB/ADS8320 laboratory testing.
    ------------------------------------------------------------------

    U_ACQUISITION_PIPELINE :
        entity work.acquisition_pipeline

        generic map (

            TEST_MODE =>
                false,

            SYS_CLK_HZ =>
                100_000_000,

            ADC_DCLOCK_HZ =>
                500_000,

            SAMPLE_RATE_HZ =>
                10_000,

            RMS_WINDOW_SAMPLES =>
                200,

            POWER_WINDOW_SAMPLES =>
                200,

            THD_FRAME_SAMPLES =>
                210

        )

        port map (

            ----------------------------------------------------------
            -- Clock/reset
            ----------------------------------------------------------

            clk_100mhz =>
                CLK100MHZ,

            reset =>
                RESET,


            ----------------------------------------------------------
            -- ADC interface
            ----------------------------------------------------------

            adc_dout_v =>
                ADC_DOUT_V,

            adc_dout_i =>
                ADC_DOUT_I,

            adc_cs_n =>
                ADC_CS_N,

            adc_dclock =>
                ADC_DCLOCK,


            ----------------------------------------------------------
            -- Raw ADC values
            ----------------------------------------------------------

            voltage_raw =>
                voltage_raw,

            current_raw =>
                current_raw,


            ----------------------------------------------------------
            -- Signed samples
            ----------------------------------------------------------

            voltage_signed_out =>
                voltage_signed,

            current_signed_out =>
                current_signed,


            ----------------------------------------------------------
            -- Instantaneous scaled samples
            ----------------------------------------------------------

            voltage_mV =>
                voltage_mV,

            current_uA =>
                current_uA,


            ----------------------------------------------------------
            -- RMS
            ----------------------------------------------------------

            voltage_rms_mV =>
                voltage_rms_mV,

            current_rms_uA =>
                current_rms_uA,


            ----------------------------------------------------------
            -- Frequency
            ----------------------------------------------------------

            frequency_mHz =>
                frequency_mHz,


            ----------------------------------------------------------
            -- Power
            ----------------------------------------------------------

            active_power_mW =>
                active_power_mW,

            apparent_power_mVA =>
                apparent_power_mVA,

            power_factor_milli =>
                power_factor_milli,


            ----------------------------------------------------------
            -- THD
            ----------------------------------------------------------

            voltage_thd_x100 =>
                voltage_thd_x100,

            current_thd_x100 =>
                current_thd_x100,


            ----------------------------------------------------------
            -- Valid strobes
            ----------------------------------------------------------

            sample_valid =>
                sample_valid,

            rms_valid =>
                rms_valid,

            frequency_valid =>
                frequency_valid,

            power_valid =>
                power_valid,

            thd_valid =>
                thd_valid

        );



    ------------------------------------------------------------------
    -- DUAL FPGA-TO-PC PACKET TRANSMITTER
    --
    -- AA55
    -- ----
    -- Existing 28-byte PQ metric packet.
    --
    -- AA56
    -- ----
    -- V/I waveform/reference frame containing both the original
    -- 16-bit ADC codes and the scaled engineering-unit samples.
    --
    -- Updated reference capture:
    --
    -- 1000 samples @ 10 kS/s
    --
    --      1000
    --      ---- = 0.1 s
    --      10000
    --
    -- = 100 ms
    --
    -- = approximately five complete cycles at 50 Hz.
    --
    -- Protocol version 02 uses 12 bytes per V/I sample pair. A
    -- 1000-pair frame takes about 1.04 s at 115200 baud, so capture
    -- starts approximately once every two seconds.
    ------------------------------------------------------------------

    U_PQ_UART_PACKET_TX :
        entity work.pq_uart_packet_tx

        generic map (

            SAMPLE_RATE_HZ =>
                10_000,


            ----------------------------------------------------------
            -- 100 ms waveform/reference frame
            ----------------------------------------------------------

            SAMPLE_FRAME_SAMPLES =>
                1_000,


            ----------------------------------------------------------
            -- Initiate a new frame approximately every two seconds.
            ----------------------------------------------------------

            FRAME_PERIOD_SAMPLES =>
                20_000

        )

        port map (

            ----------------------------------------------------------
            -- Clock/reset
            ----------------------------------------------------------

            clk_100mhz =>
                CLK100MHZ,

            reset =>
                RESET,


            ----------------------------------------------------------
            -- Instantaneous V/I data
            --
            -- This point is downstream of TEST_MODE selection.
            --
            -- Therefore the exact same packet path works for:
            --
            -- internal FPGA data now
            --
            -- and
            --
            -- real PCB/ADC data later.
            ----------------------------------------------------------

            voltage_raw_in =>
                voltage_raw,

            current_raw_in =>
                current_raw,

            voltage_mV_in =>
                voltage_mV,

            current_uA_in =>
                current_uA,

            sample_valid =>
                sample_valid,


            ----------------------------------------------------------
            -- FPGA-computed metrics
            ----------------------------------------------------------

            voltage_rms_mV =>
                voltage_rms_mV,

            current_rms_uA =>
                current_rms_uA,

            frequency_mHz =>
                frequency_mHz,

            active_power_mW =>
                active_power_mW,

            apparent_power_mVA =>
                apparent_power_mVA,

            power_factor_milli =>
                power_factor_milli,

            voltage_thd_x100 =>
                voltage_thd_x100,

            current_thd_x100 =>
                current_thd_x100,


            ----------------------------------------------------------
            -- A completed THD calculation triggers a fresh
            -- full metric packet.
            ----------------------------------------------------------

            metric_trigger =>
                thd_valid,


            ----------------------------------------------------------
            -- Byte-level UART interface
            ----------------------------------------------------------

            uart_busy =>
                uart_busy,

            uart_data =>
                uart_data,

            uart_start =>
                uart_start,


            ----------------------------------------------------------
            -- Optional transmitter activity indication
            ----------------------------------------------------------

            packet_busy =>
                packet_busy

        );



    ------------------------------------------------------------------
    -- UART TRANSMITTER
    --
    -- 115200 baud
    -- 8 data bits
    -- no parity
    -- 1 stop bit
    ------------------------------------------------------------------

    U_UART_TX :
        entity work.uart_tx

        generic map (

            CLK_FREQ_HZ =>
                100_000_000,

            BAUD_RATE =>
                115_200

        )

        port map (

            clk_100mhz =>
                CLK100MHZ,

            reset =>
                RESET,

            tx_data =>
                uart_data,

            tx_start =>
                uart_start,

            tx =>
                UART_TX,

            tx_busy =>
                uart_busy

        );


end architecture rtl;
