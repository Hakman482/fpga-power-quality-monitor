library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;


entity tb_acquisition_pipeline is
end entity tb_acquisition_pipeline;


architecture simulation of tb_acquisition_pipeline is


    ------------------------------------------------------------------
    -- FPGA clock
    ------------------------------------------------------------------
    constant CLK_PERIOD : time := 10 ns;


    ------------------------------------------------------------------
    -- Operating conditions
    ------------------------------------------------------------------
    constant SAMPLE_RATE_HZ : integer := 10000;

    constant SAMPLES_PER_CYCLE : integer := 200;

    constant TEST_CYCLES : integer := 3;

    constant TOTAL_SAMPLES :
        integer := SAMPLES_PER_CYCLE * TEST_CYCLES;


    ------------------------------------------------------------------
    -- Synthetic waveform
    ------------------------------------------------------------------
    constant VOLTAGE_PEAK_MV :
        integer := 325000;

    constant CURRENT_PEAK_UA :
        integer := 1000000;

    ------------------------------------------------------------------
    -- Current lag
    ------------------------------------------------------------------
    constant CURRENT_PHASE_DEG :
        real := 60.0;


    ------------------------------------------------------------------
    -- Nominal conversion factors previously derived
    ------------------------------------------------------------------
    constant VOLTAGE_SCALE :
        real := 15.297;

    constant CURRENT_SCALE :
        real := 47.684;


    ------------------------------------------------------------------
    -- Expected physical results
    ------------------------------------------------------------------
    constant EXPECTED_VRMS_MV :
        integer := 229810;

    constant EXPECTED_IRMS_UA :
        integer := 707107;

    constant EXPECTED_FREQ_MHZ :
        integer := 50000;

    constant EXPECTED_P_MW :
        integer := 81250;

    constant EXPECTED_S_MVA :
        integer := 162500;

    constant EXPECTED_PF :
        integer := 500;


    ------------------------------------------------------------------
    -- FPGA system
    ------------------------------------------------------------------
    signal clk_100mhz :
        std_logic := '0';

    signal reset :
        std_logic := '1';


    ------------------------------------------------------------------
    -- ADC serial interface
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
    -- Behavioural ADC sample values
    ------------------------------------------------------------------
    signal sample_v :
        std_logic_vector(15 downto 0) := x"8000";

    signal sample_i :
        std_logic_vector(15 downto 0) := x"8000";


    ------------------------------------------------------------------
    -- Pipeline intermediate outputs
    ------------------------------------------------------------------
    signal voltage_raw :
        std_logic_vector(15 downto 0);

    signal current_raw :
        std_logic_vector(15 downto 0);


    signal voltage_signed_out :
        signed(16 downto 0);

    signal current_signed_out :
        signed(16 downto 0);


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
    -- Valid signals
    ------------------------------------------------------------------
    signal sample_valid :
        std_logic;

    signal rms_valid :
        std_logic;

    signal frequency_valid :
        std_logic;

    signal power_valid :
        std_logic;


    ------------------------------------------------------------------
    -- Captured RMS result
    ------------------------------------------------------------------
    signal captured_vrms :
        unsigned(31 downto 0) := (others => '0');

    signal captured_irms :
        unsigned(31 downto 0) := (others => '0');

    signal rms_seen :
        std_logic := '0';


    ------------------------------------------------------------------
    -- Captured frequency
    ------------------------------------------------------------------
    signal captured_frequency :
        unsigned(31 downto 0) := (others => '0');

    signal frequency_seen :
        std_logic := '0';


    ------------------------------------------------------------------
    -- Captured power results
    ------------------------------------------------------------------
    signal captured_active_power :
        signed(31 downto 0) := (others => '0');

    signal captured_apparent_power :
        unsigned(31 downto 0) := (others => '0');

    signal captured_pf :
        signed(15 downto 0) := (others => '0');

    signal power_seen :
        std_logic := '0';


    ------------------------------------------------------------------
    -- Simulation control
    ------------------------------------------------------------------
    signal sim_done :
        boolean := false;


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
    -- Full acquisition pipeline
    ------------------------------------------------------------------
    DUT : entity work.acquisition_pipeline

        generic map (

            SYS_CLK_HZ =>
                100_000_000,

            ADC_DCLOCK_HZ =>
                2_000_000,

            SAMPLE_RATE_HZ =>
                10_000,

            RMS_WINDOW_SAMPLES =>
                200,

            POWER_WINDOW_SAMPLES =>
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


            sample_valid =>
                sample_valid,

            rms_valid =>
                rms_valid,

            frequency_valid =>
                frequency_valid,

            power_valid =>
                power_valid

        );



    ------------------------------------------------------------------
    -- Voltage ADS8320 behavioural model
    ------------------------------------------------------------------
    ADC_VOLTAGE : entity work.ads8320_model

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
    ADC_CURRENT : entity work.ads8320_model

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
    -- Capture RMS
    ------------------------------------------------------------------
    rms_monitor : process(clk_100mhz)
    begin

        if rising_edge(clk_100mhz) then

            if reset = '1' then

                captured_vrms <=
                    (others => '0');

                captured_irms <=
                    (others => '0');

                rms_seen <= '0';


            elsif rms_valid = '1' then

                captured_vrms <=
                    voltage_rms_mV;

                captured_irms <=
                    current_rms_uA;

                rms_seen <= '1';

            end if;

        end if;

    end process;



    ------------------------------------------------------------------
    -- Capture frequency
    ------------------------------------------------------------------
    frequency_monitor : process(clk_100mhz)
    begin

        if rising_edge(clk_100mhz) then

            if reset = '1' then

                captured_frequency <=
                    (others => '0');

                frequency_seen <= '0';


            elsif frequency_valid = '1' then

                captured_frequency <=
                    frequency_mHz;

                frequency_seen <= '1';

            end if;

        end if;

    end process;



    ------------------------------------------------------------------
    -- Capture power
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

                power_seen <= '0';


            elsif power_valid = '1' then

                captured_active_power <=
                    active_power_mW;

                captured_apparent_power <=
                    apparent_power_mVA;

                captured_pf <=
                    power_factor_milli;

                power_seen <= '1';

            end if;

        end if;

    end process;



    ------------------------------------------------------------------
    -- Stimulus
    ------------------------------------------------------------------
    stimulus_process : process


        variable angle_v :
            real;

        variable angle_i :
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

        variable power_error :
            integer;

        variable apparent_error :
            integer;

        variable pf_error :
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
        -- Send three complete 50 Hz cycles
        ------------------------------------------------------------------
        for sample_index in 0 to TOTAL_SAMPLES - 1 loop


            ------------------------------------------------------------
            -- Wait until ADC bus is idle
            ------------------------------------------------------------
            if adc_cs_n /= '1' then

                wait until rising_edge(adc_cs_n);

            end if;


            ------------------------------------------------------------
            -- Voltage phase
            ------------------------------------------------------------
            angle_v :=
                2.0 *
                math_pi *
                real(sample_index) /
                real(SAMPLES_PER_CYCLE);


            ------------------------------------------------------------
            -- Current lags voltage by 60 degrees
            ------------------------------------------------------------
            angle_i :=
                angle_v
                -
                CURRENT_PHASE_DEG *
                math_pi /
                180.0;


            ------------------------------------------------------------
            -- Physical waveforms
            ------------------------------------------------------------
            voltage_real :=
                real(VOLTAGE_PEAK_MV) *
                sin(angle_v);


            current_real :=
                real(CURRENT_PEAK_UA) *
                sin(angle_i);


            ------------------------------------------------------------
            -- Physical value → centred ADC count
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
            -- Centred count → ADS8320 straight-binary code
            ------------------------------------------------------------
            voltage_code :=
                voltage_counts + 32768;


            current_code :=
                current_counts + 32768;


            ------------------------------------------------------------
            -- Range verification
            ------------------------------------------------------------
            assert
                (voltage_code >= 0) and
                (voltage_code <= 65535)

                report
                    "Voltage ADC code out of range"

                severity failure;


            assert
                (current_code >= 0) and
                (current_code <= 65535)

                report
                    "Current ADC code out of range"

                severity failure;


            ------------------------------------------------------------
            -- Apply ADC codes
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


            ------------------------------------------------------------
            -- Settle
            ------------------------------------------------------------
            wait for 20 ns;


            ------------------------------------------------------------
            -- Wait for conversion
            ------------------------------------------------------------
            wait until falling_edge(adc_cs_n);


            ------------------------------------------------------------
            -- Wait until the current sample reaches physical scaling
            ------------------------------------------------------------
            wait until rising_edge(sample_valid);


        end loop;



        ----------------------------------------------------------------
        -- Allow the final RMS/power pipeline transactions to finish
        ------------------------------------------------------------------
        wait for 2 us;



        ----------------------------------------------------------------
        -- Check that all measurement blocks produced results
        ------------------------------------------------------------------
        assert rms_seen = '1'

            report
                "No RMS result produced"

            severity error;


        assert frequency_seen = '1'

            report
                "No frequency result produced"

            severity error;


        assert power_seen = '1'

            report
                "No power result produced"

            severity error;



        ----------------------------------------------------------------
        -- Calculate errors
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


        power_error :=
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



        ----------------------------------------------------------------
        -- RMS checks
        ------------------------------------------------------------------
        assert vrms_error <= 150

            report
                "FULL PIPELINE VRMS FAIL: measured " &
                integer'image(
                    to_integer(captured_vrms)
                ) &
                " mV"

            severity error;


        assert irms_error <= 250

            report
                "FULL PIPELINE IRMS FAIL: measured " &
                integer'image(
                    to_integer(captured_irms)
                ) &
                " uA"

            severity error;



        ----------------------------------------------------------------
        -- Frequency check
        ------------------------------------------------------------------
        assert frequency_error <= 300

            report
                "FULL PIPELINE FREQUENCY FAIL: measured " &
                integer'image(
                    to_integer(captured_frequency)
                ) &
                " mHz"

            severity error;



        ----------------------------------------------------------------
        -- Active-power check
        ------------------------------------------------------------------
        assert power_error <= 300

            report
                "FULL PIPELINE ACTIVE POWER FAIL: measured " &
                integer'image(
                    to_integer(captured_active_power)
                ) &
                " mW"

            severity error;



        ----------------------------------------------------------------
        -- Apparent-power check
        ------------------------------------------------------------------
        assert apparent_error <= 300

            report
                "FULL PIPELINE APPARENT POWER FAIL: measured " &
                integer'image(
                    to_integer(captured_apparent_power)
                ) &
                " mVA"

            severity error;



        ----------------------------------------------------------------
        -- PF check
        ------------------------------------------------------------------
        assert pf_error <= 5

            report
                "FULL PIPELINE PF FAIL: measured " &
                integer'image(
                    to_integer(captured_pf)
                )

            severity error;



        ----------------------------------------------------------------
        -- Final PASS report
        ------------------------------------------------------------------
        report
            "FULL PQ PIPELINE PASS: Vrms=" &
            integer'image(
                to_integer(captured_vrms)
            ) &
            " mV, Irms=" &
            integer'image(
                to_integer(captured_irms)
            ) &
            " uA, Freq=" &
            integer'image(
                to_integer(captured_frequency)
            ) &
            " mHz, P=" &
            integer'image(
                to_integer(captured_active_power)
            ) &
            " mW, S=" &
            integer'image(
                to_integer(captured_apparent_power)
            ) &
            " mVA, PF=" &
            integer'image(
                to_integer(captured_pf)
            )

        severity note;


        report
            "=============================================="
        severity note;


        report
            "END-TO-END POWER QUALITY PIPELINE TEST COMPLETED"
        severity note;


        report
            "=============================================="
        severity note;



        ----------------------------------------------------------------
        -- Stop simulation
        ------------------------------------------------------------------
        sim_done <= true;

        wait;


    end process;


end architecture simulation;