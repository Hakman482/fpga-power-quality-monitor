library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;


entity tb_full_pq_pipeline is
end entity tb_full_pq_pipeline;


architecture simulation of tb_full_pq_pipeline is


    ------------------------------------------------------------------
    -- FPGA clock
    ------------------------------------------------------------------
    constant CLK_PERIOD : time := 10 ns;


    ------------------------------------------------------------------
    -- Sampling / mains
    ------------------------------------------------------------------
    constant SAMPLE_RATE_HZ :
        integer := 10_000;

    constant SAMPLES_PER_CYCLE :
        integer := 200;

    constant TEST_CYCLES :
        integer := 3;

    constant TOTAL_SAMPLES :
        integer := SAMPLES_PER_CYCLE * TEST_CYCLES;


    ------------------------------------------------------------------
    -- Voltage waveform
    --
    -- Fundamental = 325 V peak
    -- H3 = 10 %
    -- H5 = 5 %
    -- H7 = 2 %
    ------------------------------------------------------------------
    constant V1_PEAK_MV :
        integer := 325000;

    constant V3_PEAK_MV :
        integer := 32500;

    constant V5_PEAK_MV :
        integer := 16250;

    constant V7_PEAK_MV :
        integer := 6500;


    ------------------------------------------------------------------
    -- Current waveform
    --
    -- Fundamental = 1 A peak
    -- Fundamental current lags voltage by 60 degrees
    --
    -- H3 = 20 %
    -- H5 = 10 %
    ------------------------------------------------------------------
    constant I1_PEAK_UA :
        integer := 1000000;

    constant I3_PEAK_UA :
        integer := 200000;

    constant I5_PEAK_UA :
        integer := 100000;


    constant CURRENT_PHASE_DEG :
        real := 60.0;


    ------------------------------------------------------------------
    -- Conversion factors used by sample_scale_v2
    ------------------------------------------------------------------
    constant VOLTAGE_SCALE :
        real := 15.297;

    constant CURRENT_SCALE :
        real := 47.684;


    ------------------------------------------------------------------
    -- Expected RMS values
    --
    -- Voltage:
    --
    -- Vrms =
    -- 325/sqrt(2) *
    -- sqrt(1 + 0.10^2 + 0.05^2 + 0.02^2)
    --
    -- ≈ 231.287 V
    ------------------------------------------------------------------
    constant EXPECTED_VRMS_MV :
        integer := 231287;


    ------------------------------------------------------------------
    -- Current:
    --
    -- Irms =
    -- 1/sqrt(2) *
    -- sqrt(1 + 0.20^2 + 0.10^2)
    --
    -- ≈ 0.724569 A
    ------------------------------------------------------------------
    constant EXPECTED_IRMS_UA :
        integer := 724569;


    ------------------------------------------------------------------
    -- Frequency
    ------------------------------------------------------------------
    constant EXPECTED_FREQ_MHZ :
        integer := 50000;


    ------------------------------------------------------------------
    -- THD
    --
    -- Voltage:
    --
    -- sqrt(
    --      0.10^2
    --    + 0.05^2
    --    + 0.02^2
    -- )
    --
    -- = 11.36 %
    --
    -- Current:
    --
    -- sqrt(
    --      0.20^2
    --    + 0.10^2
    -- )
    --
    -- = 22.36 %
    ------------------------------------------------------------------
    constant EXPECTED_VTHD :
        integer := 1136;

    constant EXPECTED_ITHD :
        integer := 2236;


    ------------------------------------------------------------------
    -- Expected active power
    --
    -- Fundamental:
    --
    -- P1 =
    -- V1pk * I1pk / 2 * cos(60 deg)
    --
    -- = 81.25 W
    --
    -- Third harmonic:
    --
    -- P3 =
    -- V3pk * I3pk / 2
    --
    -- = 3.25 W
    --
    -- Fifth harmonic:
    --
    -- P5 =
    -- V5pk * I5pk / 2
    --
    -- = 0.8125 W
    --
    -- Therefore:
    --
    -- Ptotal ≈ 85.3125 W
    ------------------------------------------------------------------
    constant EXPECTED_P_MW :
        integer := 85313;


    ------------------------------------------------------------------
    -- Apparent power
    --
    -- S = Vrms * Irms
    --
    -- ≈ 167.584 VA
    ------------------------------------------------------------------
    constant EXPECTED_S_MVA :
        integer := 167584;


    ------------------------------------------------------------------
    -- True power factor
    --
    -- PF = P / S
    --
    -- ≈ 0.509
    --
    -- x1000 representation
    ------------------------------------------------------------------
    constant EXPECTED_PF :
        integer := 509;


    ------------------------------------------------------------------
    -- Clock / reset
    ------------------------------------------------------------------
    signal clk_100mhz :
        std_logic := '0';

    signal reset :
        std_logic := '1';

    signal sim_done :
        boolean := false;


    ------------------------------------------------------------------
    -- ADS8320 serial interface
    ------------------------------------------------------------------
    signal adc_cs_n :
        std_logic;

    signal adc_dclock :
        std_logic;

    signal adc_dout_v :
        std_logic;

    signal adc_dout_i :
        std_logic;


    ------------------------------------------------------------------
    -- ADC behavioural model input codes
    ------------------------------------------------------------------
    signal sample_v :
        std_logic_vector(15 downto 0) := x"8000";

    signal sample_i :
        std_logic_vector(15 downto 0) := x"8000";


    ------------------------------------------------------------------
    -- Raw ADC outputs
    ------------------------------------------------------------------
    signal voltage_raw :
        std_logic_vector(15 downto 0);

    signal current_raw :
        std_logic_vector(15 downto 0);


    ------------------------------------------------------------------
    -- Preprocessed ADC outputs
    ------------------------------------------------------------------
    signal voltage_signed_out :
        signed(16 downto 0);

    signal current_signed_out :
        signed(16 downto 0);


    ------------------------------------------------------------------
    -- Scaled instantaneous values
    ------------------------------------------------------------------
    signal voltage_mV :
        signed(31 downto 0);

    signal current_uA :
        signed(31 downto 0);


    ------------------------------------------------------------------
    -- RMS
    ------------------------------------------------------------------
    signal voltage_rms_mV :
        unsigned(31 downto 0);

    signal current_rms_uA :
        unsigned(31 downto 0);


    ------------------------------------------------------------------
    -- Frequency
    ------------------------------------------------------------------
    signal frequency_mHz :
        unsigned(31 downto 0);


    ------------------------------------------------------------------
    -- Power
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
    -- Valid pulses
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
    -- Captured RMS values
    ------------------------------------------------------------------
    signal captured_vrms :
        unsigned(31 downto 0) :=
        (others => '0');

    signal captured_irms :
        unsigned(31 downto 0) :=
        (others => '0');


    ------------------------------------------------------------------
    -- Captured frequency
    ------------------------------------------------------------------
    signal captured_frequency :
        unsigned(31 downto 0) :=
        (others => '0');


    ------------------------------------------------------------------
    -- Captured power
    ------------------------------------------------------------------
    signal captured_active_power :
        signed(31 downto 0) :=
        (others => '0');

    signal captured_apparent_power :
        unsigned(31 downto 0) :=
        (others => '0');

    signal captured_pf :
        signed(15 downto 0) :=
        (others => '0');


    ------------------------------------------------------------------
    -- Captured THD
    ------------------------------------------------------------------
    signal captured_vthd :
        unsigned(15 downto 0) :=
        (others => '0');

    signal captured_ithd :
        unsigned(15 downto 0) :=
        (others => '0');


    ------------------------------------------------------------------
    -- Result flags
    ------------------------------------------------------------------
    signal rms_seen :
        std_logic := '0';

    signal frequency_seen :
        std_logic := '0';

    signal power_seen :
        std_logic := '0';

    signal thd_seen :
        std_logic := '0';


begin


    ------------------------------------------------------------------
    -- 100 MHz FPGA clock
    ------------------------------------------------------------------
    clock_process : process
    begin

        while not sim_done loop

            clk_100mhz <= '0';
            wait for CLK_PERIOD / 2;

            clk_100mhz <= '1';
            wait for CLK_PERIOD / 2;

        end loop;

        clk_100mhz <= '0';

        wait;

    end process;



    ------------------------------------------------------------------
    -- FULL ACQUISITION / PQ PIPELINE
    ------------------------------------------------------------------
    DUT :
        entity work.acquisition_pipeline

        generic map (

            SYS_CLK_HZ =>
                100_000_000,

            ADC_DCLOCK_HZ =>
                2_000_000,

            SAMPLE_RATE_HZ =>
                SAMPLE_RATE_HZ,

            RMS_WINDOW_SAMPLES =>
                200,

            POWER_WINDOW_SAMPLES =>
                200,

            THD_FRAME_SAMPLES =>
                200

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


            voltage_raw =>
                voltage_raw,

            current_raw =>
                current_raw,


            voltage_signed_out =>
                voltage_signed_out,

            current_signed_out =>
                current_signed_out,


            voltage_mV =>
                voltage_mV,

            current_uA =>
                current_uA,


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
    -- Voltage ADS8320 behavioural model
    ------------------------------------------------------------------
    ADC_VOLTAGE :
        entity work.ads8320_model

        port map (

            cs_n =>
                adc_cs_n,

            dclock =>
                adc_dclock,

            sample_in =>
                sample_v,

            dout =>
                adc_dout_v

        );



    ------------------------------------------------------------------
    -- Current ADS8320 behavioural model
    ------------------------------------------------------------------
    ADC_CURRENT :
        entity work.ads8320_model

        port map (

            cs_n =>
                adc_cs_n,

            dclock =>
                adc_dclock,

            sample_in =>
                sample_i,

            dout =>
                adc_dout_i

        );



    ------------------------------------------------------------------
    -- RMS monitor
    ------------------------------------------------------------------
    rms_monitor : process(clk_100mhz)
    begin

        if rising_edge(clk_100mhz) then

            if reset = '1' then

                captured_vrms <=
                    (others => '0');

                captured_irms <=
                    (others => '0');

                rms_seen <=
                    '0';


            elsif rms_valid = '1' then

                captured_vrms <=
                    voltage_rms_mV;

                captured_irms <=
                    current_rms_uA;

                rms_seen <=
                    '1';

            end if;

        end if;

    end process;



    ------------------------------------------------------------------
    -- Frequency monitor
    ------------------------------------------------------------------
    frequency_monitor : process(clk_100mhz)
    begin

        if rising_edge(clk_100mhz) then

            if reset = '1' then

                captured_frequency <=
                    (others => '0');

                frequency_seen <=
                    '0';


            elsif frequency_valid = '1' then

                captured_frequency <=
                    frequency_mHz;

                frequency_seen <=
                    '1';

            end if;

        end if;

    end process;



    ------------------------------------------------------------------
    -- Power monitor
    ------------------------------------------------------------------
    power_monitor : process(clk_100mhz)
    begin

        if rising_edge(clk_100mhz) then

            if reset = '1' then

                captured_active_power <=
                    (others => '0');

                captured_apparent_power <=
                    (others => '0');

                captured_pf <=
                    (others => '0');

                power_seen <=
                    '0';


            elsif power_valid = '1' then

                captured_active_power <=
                    active_power_mW;

                captured_apparent_power <=
                    apparent_power_mVA;

                captured_pf <=
                    power_factor_milli;

                power_seen <=
                    '1';

            end if;

        end if;

    end process;



    ------------------------------------------------------------------
    -- THD monitor
    ------------------------------------------------------------------
    thd_monitor : process(clk_100mhz)
    begin

        if rising_edge(clk_100mhz) then

            if reset = '1' then

                captured_vthd <=
                    (others => '0');

                captured_ithd <=
                    (others => '0');

                thd_seen <=
                    '0';


            elsif thd_valid = '1' then

                captured_vthd <=
                    voltage_thd_x100;

                captured_ithd <=
                    current_thd_x100;

                thd_seen <=
                    '1';

            end if;

        end if;

    end process;



    ------------------------------------------------------------------
    -- Stimulus
    ------------------------------------------------------------------
    stimulus_process : process


        variable theta :
            real;

        variable current_theta :
            real;


        variable voltage_real :
            real;

        variable current_real :
            real;


        variable voltage_counts :
            integer;

        variable current_counts :
            integer;


        variable voltage_code :
            integer;

        variable current_code :
            integer;


        variable vrms_error :
            integer;

        variable irms_error :
            integer;

        variable frequency_error :
            integer;

        variable active_error :
            integer;

        variable apparent_error :
            integer;

        variable pf_error :
            integer;

        variable vthd_error :
            integer;

        variable ithd_error :
            integer;


    begin


        ----------------------------------------------------------------
        -- Reset
        ------------------------------------------------------------------
        reset <= '1';

        sample_v <= x"8000";
        sample_i <= x"8000";

        wait for 200 ns;

        reset <= '0';



        ----------------------------------------------------------------
        -- Generate three complete distorted 50 Hz cycles
        ------------------------------------------------------------------
        for sample_index in 0 to TOTAL_SAMPLES - 1 loop


            ------------------------------------------------------------
            -- Wait until ADC interface is idle
            ------------------------------------------------------------
            if adc_cs_n /= '1' then

                wait until rising_edge(adc_cs_n);

            end if;


            ------------------------------------------------------------
            -- Base 50 Hz phase
            ------------------------------------------------------------
            theta :=
                2.0 *
                math_pi *
                real(sample_index) /
                real(SAMPLES_PER_CYCLE);


            ------------------------------------------------------------
            -- Current fundamental lags by 60 degrees
            ------------------------------------------------------------
            current_theta :=
                theta
                -
                CURRENT_PHASE_DEG *
                math_pi /
                180.0;


            ------------------------------------------------------------
            -- Distorted voltage
            ------------------------------------------------------------
            voltage_real :=

                real(V1_PEAK_MV) *
                sin(theta)

                +

                real(V3_PEAK_MV) *
                sin(3.0 * theta)

                +

                real(V5_PEAK_MV) *
                sin(5.0 * theta)

                +

                real(V7_PEAK_MV) *
                sin(7.0 * theta);


            ------------------------------------------------------------
            -- Distorted current
            --
            -- Fundamental has 60 degree lag.
            --
            -- H3 and H5 are deliberately placed at zero phase
            -- relative to corresponding voltage harmonics.
            ------------------------------------------------------------
            current_real :=

                real(I1_PEAK_UA) *
                sin(current_theta)

                +

                real(I3_PEAK_UA) *
                sin(3.0 * theta)

                +

                real(I5_PEAK_UA) *
                sin(5.0 * theta);


            ------------------------------------------------------------
            -- Physical value -> centred ADC count
            ------------------------------------------------------------
            voltage_counts :=
                integer(
                    round(
                        voltage_real /
                        VOLTAGE_SCALE
                    )
                );


            current_counts :=
                integer(
                    round(
                        current_real /
                        CURRENT_SCALE
                    )
                );


            ------------------------------------------------------------
            -- Centred count -> straight binary ADS8320 code
            ------------------------------------------------------------
            voltage_code :=
                voltage_counts + 32768;


            current_code :=
                current_counts + 32768;


            ------------------------------------------------------------
            -- ADC range protection
            ------------------------------------------------------------
            assert
                voltage_code >= 0 and
                voltage_code <= 65535

                report
                    "FULL PQ TEST FAIL: voltage ADC code out of range"

                severity failure;


            assert
                current_code >= 0 and
                current_code <= 65535

                report
                    "FULL PQ TEST FAIL: current ADC code out of range"

                severity failure;


            ------------------------------------------------------------
            -- Apply values to behavioural ADC models
            ------------------------------------------------------------
            sample_v <=
                std_logic_vector(
                    to_unsigned(
                        voltage_code,
                        16
                    )
                );


            sample_i <=
                std_logic_vector(
                    to_unsigned(
                        current_code,
                        16
                    )
                );


            wait for 20 ns;


            ------------------------------------------------------------
            -- Wait for conversion start
            ------------------------------------------------------------
            wait until falling_edge(adc_cs_n);


            ------------------------------------------------------------
            -- Wait until sample emerges from scaling stage
            ------------------------------------------------------------
            wait until rising_edge(sample_valid);


        end loop;



        ----------------------------------------------------------------
        -- Allow final RMS / power / THD processing to complete
        ------------------------------------------------------------------
        wait for 1 ms;



        ----------------------------------------------------------------
        -- Verify that every subsystem produced a result
        ------------------------------------------------------------------
        assert rms_seen = '1'

            report
                "FULL PQ TEST FAIL: no RMS result produced"

            severity error;


        assert frequency_seen = '1'

            report
                "FULL PQ TEST FAIL: no frequency result produced"

            severity error;


        assert power_seen = '1'

            report
                "FULL PQ TEST FAIL: no power result produced"

            severity error;


        assert thd_seen = '1'

            report
                "FULL PQ TEST FAIL: no THD result produced"

            severity error;



        ----------------------------------------------------------------
        -- Calculate measurement errors
        ------------------------------------------------------------------
        vrms_error :=
            abs(
                to_integer(captured_vrms)
                -
                EXPECTED_VRMS_MV
            );


        irms_error :=
            abs(
                to_integer(captured_irms)
                -
                EXPECTED_IRMS_UA
            );


        frequency_error :=
            abs(
                to_integer(captured_frequency)
                -
                EXPECTED_FREQ_MHZ
            );


        active_error :=
            abs(
                to_integer(captured_active_power)
                -
                EXPECTED_P_MW
            );


        apparent_error :=
            abs(
                to_integer(captured_apparent_power)
                -
                EXPECTED_S_MVA
            );


        pf_error :=
            abs(
                to_integer(captured_pf)
                -
                EXPECTED_PF
            );


        vthd_error :=
            abs(
                to_integer(captured_vthd)
                -
                EXPECTED_VTHD
            );


        ithd_error :=
            abs(
                to_integer(captured_ithd)
                -
                EXPECTED_ITHD
            );



        ----------------------------------------------------------------
        -- RMS verification
        ------------------------------------------------------------------
        assert vrms_error <= 1200

            report
                "FULL PQ VRMS FAIL: expected approximately " &
                integer'image(EXPECTED_VRMS_MV) &
                " mV, measured " &
                integer'image(
                    to_integer(captured_vrms)
                ) &
                " mV"

            severity error;


        assert irms_error <= 3500

            report
                "FULL PQ IRMS FAIL: expected approximately " &
                integer'image(EXPECTED_IRMS_UA) &
                " uA, measured " &
                integer'image(
                    to_integer(captured_irms)
                ) &
                " uA"

            severity error;



        ----------------------------------------------------------------
        -- Frequency verification
        ------------------------------------------------------------------
        assert frequency_error <= 500

            report
                "FULL PQ FREQUENCY FAIL: expected approximately " &
                integer'image(EXPECTED_FREQ_MHZ) &
                " mHz, measured " &
                integer'image(
                    to_integer(captured_frequency)
                ) &
                " mHz"

            severity error;



        ----------------------------------------------------------------
        -- Active power verification
        ------------------------------------------------------------------
        assert active_error <= 2500

            report
                "FULL PQ ACTIVE POWER FAIL: expected approximately " &
                integer'image(EXPECTED_P_MW) &
                " mW, measured " &
                integer'image(
                    to_integer(captured_active_power)
                ) &
                " mW"

            severity error;



        ----------------------------------------------------------------
        -- Apparent power verification
        ------------------------------------------------------------------
        assert apparent_error <= 2500

            report
                "FULL PQ APPARENT POWER FAIL: expected approximately " &
                integer'image(EXPECTED_S_MVA) &
                " mVA, measured " &
                integer'image(
                    to_integer(captured_apparent_power)
                ) &
                " mVA"

            severity error;



        ----------------------------------------------------------------
        -- PF verification
        ------------------------------------------------------------------
        assert pf_error <= 30

            report
                "FULL PQ PF FAIL: expected approximately " &
                integer'image(EXPECTED_PF) &
                ", measured " &
                integer'image(
                    to_integer(captured_pf)
                )

            severity error;



        ----------------------------------------------------------------
        -- Voltage THD verification
        ------------------------------------------------------------------
        assert vthd_error <= 100

            report
                "FULL PQ VTHD FAIL: expected approximately " &
                integer'image(EXPECTED_VTHD) &
                ", measured " &
                integer'image(
                    to_integer(captured_vthd)
                )

            severity error;



        ----------------------------------------------------------------
        -- Current THD verification
        ------------------------------------------------------------------
        assert ithd_error <= 120

            report
                "FULL PQ ITHD FAIL: expected approximately " &
                integer'image(EXPECTED_ITHD) &
                ", measured " &
                integer'image(
                    to_integer(captured_ithd)
                )

            severity error;



        ----------------------------------------------------------------
        -- Final PASS report
        ------------------------------------------------------------------
        report
            "=================================================="
        severity note;


        report
            "FULL FPGA POWER QUALITY PIPELINE PASS"
        severity note;


        report
            "Vrms = " &
            integer'image(
                to_integer(captured_vrms)
            ) &
            " mV"
        severity note;


        report
            "Irms = " &
            integer'image(
                to_integer(captured_irms)
            ) &
            " uA"
        severity note;


        report
            "Frequency = " &
            integer'image(
                to_integer(captured_frequency)
            ) &
            " mHz"
        severity note;


        report
            "Active Power = " &
            integer'image(
                to_integer(captured_active_power)
            ) &
            " mW"
        severity note;


        report
            "Apparent Power = " &
            integer'image(
                to_integer(captured_apparent_power)
            ) &
            " mVA"
        severity note;


        report
            "Power Factor x1000 = " &
            integer'image(
                to_integer(captured_pf)
            )
        severity note;


        report
            "Voltage THD x100 = " &
            integer'image(
                to_integer(captured_vthd)
            )
        severity note;


        report
            "Current THD x100 = " &
            integer'image(
                to_integer(captured_ithd)
            )
        severity note;


        report
            "=================================================="
        severity note;



        ----------------------------------------------------------------
        -- Stop simulation
        ------------------------------------------------------------------
        sim_done <= true;

        wait;


    end process;


end architecture simulation;