library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity acquisition_pipeline is

    generic (

        --------------------------------------------------------------
        -- TEST MODE
        --
        -- true:
        --     use internal synthetic waveform source
        --
        -- false:
        --     use real ADS8320 ADC interfaces
        --------------------------------------------------------------
        TEST_MODE :
            boolean := false;


        --------------------------------------------------------------
        -- System / ADC
        --------------------------------------------------------------
        SYS_CLK_HZ :
            integer := 100_000_000;

        ADC_DCLOCK_HZ :
            integer := 2_000_000;

        SAMPLE_RATE_HZ :
            integer := 10_000;


        --------------------------------------------------------------
        -- RMS
        --------------------------------------------------------------
        RMS_WINDOW_SAMPLES :
            positive := 200;


        --------------------------------------------------------------
        -- Power
        --------------------------------------------------------------
        POWER_WINDOW_SAMPLES :
            positive := 200;


        --------------------------------------------------------------
        -- THD
        --
        -- Maximum permitted adaptive cycle length.
        --------------------------------------------------------------
        THD_FRAME_SAMPLES :
            positive := 210

    );

    port (

        --------------------------------------------------------------
        -- FPGA
        --------------------------------------------------------------
        clk_100mhz :
            in std_logic;

        reset :
            in std_logic;


        --------------------------------------------------------------
        -- ADS8320 serial interfaces
        --------------------------------------------------------------
        adc_dout_v :
            in std_logic;

        adc_dout_i :
            in std_logic;


        adc_cs_n :
            out std_logic;

        adc_dclock :
            out std_logic;


        --------------------------------------------------------------
        -- Raw ADC samples
        --------------------------------------------------------------
        voltage_raw :
            out std_logic_vector(15 downto 0);

        current_raw :
            out std_logic_vector(15 downto 0);


        --------------------------------------------------------------
        -- Zero-centred ADC counts
        --------------------------------------------------------------
        voltage_signed_out :
            out signed(16 downto 0);

        current_signed_out :
            out signed(16 downto 0);


        --------------------------------------------------------------
        -- Instantaneous physical quantities
        --------------------------------------------------------------
        voltage_mV :
            out signed(31 downto 0);

        current_uA :
            out signed(31 downto 0);


        --------------------------------------------------------------
        -- RMS
        --------------------------------------------------------------
        voltage_rms_mV :
            out unsigned(31 downto 0);

        current_rms_uA :
            out unsigned(31 downto 0);


        --------------------------------------------------------------
        -- Frequency
        --------------------------------------------------------------
        frequency_mHz :
            out unsigned(31 downto 0);


        --------------------------------------------------------------
        -- Power
        --------------------------------------------------------------
        active_power_mW :
            out signed(31 downto 0);

        apparent_power_mVA :
            out unsigned(31 downto 0);

        power_factor_milli :
            out signed(15 downto 0);


        --------------------------------------------------------------
        -- THD
        --------------------------------------------------------------
        voltage_thd_x100 :
            out unsigned(15 downto 0);

        current_thd_x100 :
            out unsigned(15 downto 0);


        --------------------------------------------------------------
        -- THD DIAGNOSTIC
        --
        -- Actual samples in the most recently captured
        -- electrical-cycle frame.
        --
        -- Renamed to avoid collision with generic
        -- THD_FRAME_SAMPLES because VHDL is case-insensitive.
        --------------------------------------------------------------
        thd_frame_count_debug :
            out unsigned(15 downto 0);


        --------------------------------------------------------------
        -- Valid pulses
        --------------------------------------------------------------
        sample_valid :
            out std_logic;

        rms_valid :
            out std_logic;

        frequency_valid :
            out std_logic;

        power_valid :
            out std_logic;

        thd_valid :
            out std_logic

    );

end entity acquisition_pipeline;



architecture rtl of acquisition_pipeline is


    ------------------------------------------------------------------
    -- STAGE 1:
    -- ADC
    ------------------------------------------------------------------

    signal voltage_raw_int :
        std_logic_vector(15 downto 0);

    signal current_raw_int :
        std_logic_vector(15 downto 0);

    signal adc_valid_int :
        std_logic;



    ------------------------------------------------------------------
    -- STAGE 2:
    -- Preprocessing / test-source selection
    ------------------------------------------------------------------

    signal voltage_signed_int :
        signed(16 downto 0);

    signal current_signed_int :
        signed(16 downto 0);

    signal preprocess_valid_int :
        std_logic;



    ------------------------------------------------------------------
    -- Internal synthetic source
    ------------------------------------------------------------------

    signal test_voltage_signed :
        signed(16 downto 0);

    signal test_current_signed :
        signed(16 downto 0);

    signal test_sample_valid :
        std_logic;



    ------------------------------------------------------------------
    -- STAGE 3:
    -- Physical scaling
    ------------------------------------------------------------------

    signal voltage_mV_int :
        signed(31 downto 0);

    signal current_uA_int :
        signed(31 downto 0);

    signal scale_valid_int :
        std_logic;



    ------------------------------------------------------------------
    -- STAGE 4:
    -- RMS
    ------------------------------------------------------------------

    signal voltage_rms_mV_int :
        unsigned(31 downto 0);

    signal current_rms_uA_int :
        unsigned(31 downto 0);

    signal rms_valid_int :
        std_logic;



    ------------------------------------------------------------------
    -- STAGE 5:
    -- Frequency
    ------------------------------------------------------------------

    signal frequency_mHz_int :
        unsigned(31 downto 0);

    signal frequency_valid_int :
        std_logic;



    ------------------------------------------------------------------
    -- STAGE 6:
    -- Power
    ------------------------------------------------------------------

    signal active_power_mW_int :
        signed(31 downto 0);

    signal apparent_power_mVA_int :
        unsigned(31 downto 0);

    signal power_factor_milli_int :
        signed(15 downto 0);

    signal power_valid_int :
        std_logic;



    ------------------------------------------------------------------
    -- STAGE 7:
    -- THD frame buffer
    ------------------------------------------------------------------

    signal thd_frame_valid :
        std_logic;


    signal thd_frame_sample_count :
        unsigned(15 downto 0);


    signal thd_read_index :
        unsigned(15 downto 0);


    signal thd_voltage_sample :
        signed(31 downto 0);


    signal thd_current_sample :
        signed(31 downto 0);



    ------------------------------------------------------------------
    -- STAGE 8:
    -- Harmonic extractor
    ------------------------------------------------------------------

    signal voltage_fund_mag_sq_int :
        unsigned(79 downto 0);


    signal current_fund_mag_sq_int :
        unsigned(79 downto 0);


    signal voltage_harm_sum_sq_int :
        unsigned(84 downto 0);


    signal current_harm_sum_sq_int :
        unsigned(84 downto 0);


    signal harmonic_number_int :
        unsigned(5 downto 0);


    signal harmonic_busy_int :
        std_logic;


    signal harmonic_valid_int :
        std_logic;



    ------------------------------------------------------------------
    -- STAGE 9:
    -- THD meter
    ------------------------------------------------------------------

    signal voltage_thd_x100_int :
        unsigned(15 downto 0);


    signal current_thd_x100_int :
        unsigned(15 downto 0);


    signal thd_valid_int :
        std_logic;



begin


    ------------------------------------------------------------------
    -- External output assignments
    ------------------------------------------------------------------

    voltage_raw <=
        voltage_raw_int;


    current_raw <=
        current_raw_int;


    voltage_signed_out <=
        voltage_signed_int;


    current_signed_out <=
        current_signed_int;


    voltage_mV <=
        voltage_mV_int;


    current_uA <=
        current_uA_int;


    voltage_rms_mV <=
        voltage_rms_mV_int;


    current_rms_uA <=
        current_rms_uA_int;


    frequency_mHz <=
        frequency_mHz_int;


    active_power_mW <=
        active_power_mW_int;


    apparent_power_mVA <=
        apparent_power_mVA_int;


    power_factor_milli <=
        power_factor_milli_int;


    voltage_thd_x100 <=
        voltage_thd_x100_int;


    current_thd_x100 <=
        current_thd_x100_int;



    ------------------------------------------------------------------
    -- THD diagnostic
    ------------------------------------------------------------------

    thd_frame_count_debug <=
        thd_frame_sample_count;



    ------------------------------------------------------------------
    -- Valid outputs
    ------------------------------------------------------------------

    sample_valid <=
        scale_valid_int;


    rms_valid <=
        rms_valid_int;


    frequency_valid <=
        frequency_valid_int;


    power_valid <=
        power_valid_int;


    thd_valid <=
        thd_valid_int;



    ------------------------------------------------------------------
    -- TEST MODE
    ------------------------------------------------------------------

    TEST_MODE_GEN :
    if TEST_MODE generate


        TEST_SOURCE :
            entity work.test_signal_source

            generic map (

                CLK_FREQ_HZ =>
                    SYS_CLK_HZ,

                SAMPLE_RATE_HZ =>
                    SAMPLE_RATE_HZ

            )

            port map (

                clk_100mhz =>
                    clk_100mhz,

                reset =>
                    reset,


                voltage_signed_out =>
                    test_voltage_signed,

                current_signed_out =>
                    test_current_signed,


                sample_valid_out =>
                    test_sample_valid

            );



        --------------------------------------------------------------
        -- Synthetic source already provides signed, zero-centred
        -- ADC-equivalent samples.
        --------------------------------------------------------------

        voltage_signed_int <=
            test_voltage_signed;


        current_signed_int <=
            test_current_signed;


        preprocess_valid_int <=
            test_sample_valid;



        --------------------------------------------------------------
        -- Disable physical ADC pins in test mode.
        --------------------------------------------------------------

        adc_cs_n <=
            '1';


        adc_dclock <=
            '0';


        voltage_raw_int <=
            (others => '0');


        current_raw_int <=
            (others => '0');


        adc_valid_int <=
            '0';


    end generate TEST_MODE_GEN;



    ------------------------------------------------------------------
    -- REAL ADC MODE
    ------------------------------------------------------------------

    REAL_ADC_MODE_GEN :
    if not TEST_MODE generate


        --------------------------------------------------------------
        -- STAGE 1
        -- Dual ADS8320 interface
        --------------------------------------------------------------

        ADC_INTERFACE :
            entity work.dual_adc_if

            generic map (

                SYS_CLK_HZ =>
                    SYS_CLK_HZ,

                ADC_DCLOCK_HZ =>
                    ADC_DCLOCK_HZ,

                SAMPLE_RATE_HZ =>
                    SAMPLE_RATE_HZ

            )

            port map (

                clk_100mhz =>
                    clk_100mhz,

                reset =>
                    reset,


                adc_dout_v =>
                    adc_dout_v,

                adc_dout_i =>
                    adc_dout_i,


                adc_cs_n =>
                    adc_cs_n,

                adc_dclock =>
                    adc_dclock,


                voltage_data =>
                    voltage_raw_int,

                current_data =>
                    current_raw_int,


                sample_valid =>
                    adc_valid_int

            );



        --------------------------------------------------------------
        -- STAGE 2
        -- ADC midpoint removal
        --------------------------------------------------------------

        PREPROCESS :
            entity work.sample_preprocess

            port map (

                clk_100mhz =>
                    clk_100mhz,

                reset =>
                    reset,


                voltage_raw =>
                    voltage_raw_int,

                current_raw =>
                    current_raw_int,


                sample_valid_in =>
                    adc_valid_int,


                voltage_signed =>
                    voltage_signed_int,

                current_signed =>
                    current_signed_int,


                sample_valid_out =>
                    preprocess_valid_int

            );


    end generate REAL_ADC_MODE_GEN;



    ------------------------------------------------------------------
    -- STAGE 3
    -- ADC counts -> physical units
    ------------------------------------------------------------------

    SCALE :
        entity work.sample_scale_v2

        port map (

            clk_100mhz =>
                clk_100mhz,

            reset =>
                reset,


            voltage_signed_in =>
                voltage_signed_int,

            current_signed_in =>
                current_signed_int,


            sample_valid_in =>
                preprocess_valid_int,


            voltage_mV =>
                voltage_mV_int,

            current_uA =>
                current_uA_int,


            sample_valid_out =>
                scale_valid_int

        );



    ------------------------------------------------------------------
    -- STAGE 4
    -- Cycle-synchronous RMS
    ------------------------------------------------------------------

    RMS_BLOCK :
        entity work.dual_rms

        generic map (

            WINDOW_SAMPLES =>
                RMS_WINDOW_SAMPLES

        )

        port map (

            clk_100mhz =>
                clk_100mhz,

            reset =>
                reset,


            voltage_mV_in =>
                voltage_mV_int,

            current_uA_in =>
                current_uA_int,


            sample_valid_in =>
                scale_valid_int,


            voltage_rms_mV =>
                voltage_rms_mV_int,

            current_rms_uA =>
                current_rms_uA_int,


            rms_valid =>
                rms_valid_int

        );



    ------------------------------------------------------------------
    -- STAGE 5
    -- Frequency meter
    ------------------------------------------------------------------

    FREQUENCY_BLOCK :
        entity work.frequency_meter

        generic map (

            SYS_CLK_HZ =>
                SYS_CLK_HZ

        )

        port map (

            clk_100mhz =>
                clk_100mhz,

            reset =>
                reset,


            voltage_mV_in =>
                voltage_mV_int,


            sample_valid_in =>
                scale_valid_int,


            frequency_mHz =>
                frequency_mHz_int,


            frequency_valid =>
                frequency_valid_int

        );



    ------------------------------------------------------------------
    -- STAGE 6
    -- Cycle-synchronous power
    ------------------------------------------------------------------

    POWER_BLOCK :
        entity work.power_meter_v2

        generic map (

            WINDOW_SAMPLES =>
                POWER_WINDOW_SAMPLES

        )

        port map (

            clk_100mhz =>
                clk_100mhz,

            reset =>
                reset,


            voltage_mV_in =>
                voltage_mV_int,

            current_uA_in =>
                current_uA_int,


            sample_valid_in =>
                scale_valid_int,


            voltage_rms_mV_in =>
                voltage_rms_mV_int,

            current_rms_uA_in =>
                current_rms_uA_int,


            rms_valid_in =>
                rms_valid_int,


            active_power_mW =>
                active_power_mW_int,


            apparent_power_mVA =>
                apparent_power_mVA_int,


            power_factor_milli =>
                power_factor_milli_int,


            power_valid =>
                power_valid_int

        );



    ------------------------------------------------------------------
    -- STAGE 7
    -- Cycle-synchronous XPM-BRAM frame buffer
    ------------------------------------------------------------------

    THD_FRAME_BUFFER :
        entity work.sample_frame_buffer

        generic map (

            FRAME_SAMPLES =>
                THD_FRAME_SAMPLES

        )

        port map (

            clk_100mhz =>
                clk_100mhz,

            reset =>
                reset,


            voltage_mV_in =>
                voltage_mV_int,

            current_uA_in =>
                current_uA_int,


            sample_valid_in =>
                scale_valid_int,


            frame_valid =>
                thd_frame_valid,


            sample_count_out =>
                thd_frame_sample_count,


            read_index =>
                thd_read_index,


            voltage_mV_out =>
                thd_voltage_sample,

            current_uA_out =>
                thd_current_sample

        );



    ------------------------------------------------------------------
    -- STAGE 8
    -- Exact frame-length Goertzel harmonic extraction
    ------------------------------------------------------------------

    HARMONIC_BLOCK :
        entity work.harmonic_1_25_extractor

        generic map (

            FRAME_SAMPLES =>
                THD_FRAME_SAMPLES

        )

        port map (

            clk_100mhz =>
                clk_100mhz,

            reset =>
                reset,


            start =>
                thd_frame_valid,


            frame_sample_count =>
                thd_frame_sample_count,


            read_index =>
                thd_read_index,


            voltage_sample_mV =>
                thd_voltage_sample,

            current_sample_uA =>
                thd_current_sample,


            voltage_fund_mag_sq =>
                voltage_fund_mag_sq_int,

            current_fund_mag_sq =>
                current_fund_mag_sq_int,


            voltage_harm_sum_sq =>
                voltage_harm_sum_sq_int,

            current_harm_sum_sq =>
                current_harm_sum_sq_int,


            harmonic_number =>
                harmonic_number_int,


            busy =>
                harmonic_busy_int,


            harmonic_valid =>
                harmonic_valid_int

        );



    ------------------------------------------------------------------
    -- STAGE 9
    -- Final THD calculation
    ------------------------------------------------------------------

    THD_BLOCK :
        entity work.thd_1_25_meter

        port map (

            clk_100mhz =>
                clk_100mhz,

            reset =>
                reset,


            voltage_fund_mag_sq =>
                voltage_fund_mag_sq_int,

            current_fund_mag_sq =>
                current_fund_mag_sq_int,


            voltage_harm_sum_sq =>
                voltage_harm_sum_sq_int,

            current_harm_sum_sq =>
                current_harm_sum_sq_int,


            harmonic_valid_in =>
                harmonic_valid_int,


            voltage_thd_x100 =>
                voltage_thd_x100_int,

            current_thd_x100 =>
                current_thd_x100_int,


            thd_valid =>
                thd_valid_int

        );


end architecture rtl;