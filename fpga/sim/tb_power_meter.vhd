library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity tb_power_meter is
end entity tb_power_meter;


architecture simulation of tb_power_meter is

    ------------------------------------------------------------------
    -- FPGA clock
    ------------------------------------------------------------------
    constant CLK_PERIOD : time := 10 ns;

    ------------------------------------------------------------------
    -- Real project window
    ------------------------------------------------------------------
    constant WINDOW_SAMPLES : integer := 200;

    ------------------------------------------------------------------
    -- DUT inputs
    ------------------------------------------------------------------
    signal clk_100mhz : std_logic := '0';
    signal reset      : std_logic := '1';

    signal voltage_mV_in :
        signed(31 downto 0) := (others => '0');

    signal current_uA_in :
        signed(31 downto 0) := (others => '0');

    signal sample_valid_in :
        std_logic := '0';

    signal voltage_rms_mV_in :
        unsigned(31 downto 0) := (others => '0');

    signal current_rms_uA_in :
        unsigned(31 downto 0) := (others => '0');

    ------------------------------------------------------------------
    -- DUT outputs
    ------------------------------------------------------------------
    signal active_power_mW :
        signed(31 downto 0);

    signal apparent_power_mVA :
        unsigned(31 downto 0);

    signal power_factor_milli :
        signed(15 downto 0);

    signal power_valid :
        std_logic;

    ------------------------------------------------------------------
    -- Captured DUT result
    --
    -- These prevent the testbench from missing the one-clock
    -- power_valid pulse.
    ------------------------------------------------------------------
    signal captured_active_power_mW :
        signed(31 downto 0) := (others => '0');

    signal captured_apparent_power_mVA :
        unsigned(31 downto 0) := (others => '0');

    signal captured_power_factor_milli :
        signed(15 downto 0) := (others => '0');

    signal captured_valid :
        std_logic := '0';

    ------------------------------------------------------------------
    -- Simulation control
    ------------------------------------------------------------------
    signal sim_done : boolean := false;


begin


    ------------------------------------------------------------------
    -- 100 MHz clock
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
    -- DUT
    ------------------------------------------------------------------
    DUT : entity work.power_meter

        generic map (
            WINDOW_SAMPLES => WINDOW_SAMPLES
        )

        port map (

            clk_100mhz => clk_100mhz,
            reset      => reset,

            voltage_mV_in => voltage_mV_in,
            current_uA_in => current_uA_in,

            sample_valid_in => sample_valid_in,

            voltage_rms_mV_in => voltage_rms_mV_in,
            current_rms_uA_in => current_rms_uA_in,

            active_power_mW => active_power_mW,
            apparent_power_mVA => apparent_power_mVA,
            power_factor_milli => power_factor_milli,

            power_valid => power_valid
        );


    ------------------------------------------------------------------
    -- POWER RESULT MONITOR
    ------------------------------------------------------------------
    monitor_process : process(clk_100mhz)
    begin

        if rising_edge(clk_100mhz) then

            if reset = '1' then

                captured_active_power_mW <= (others => '0');
                captured_apparent_power_mVA <= (others => '0');
                captured_power_factor_milli <= (others => '0');

                captured_valid <= '0';

            else

                if power_valid = '1' then

                    captured_active_power_mW <= active_power_mW;

                    captured_apparent_power_mVA <=
                        apparent_power_mVA;

                    captured_power_factor_milli <=
                        power_factor_milli;

                    captured_valid <= '1';

                end if;

            end if;

        end if;

    end process;


    ------------------------------------------------------------------
    -- Stimulus
    ------------------------------------------------------------------
    stimulus_process : process


        ----------------------------------------------------------------
        -- Send one synchronized sample pair
        ----------------------------------------------------------------
        procedure send_sample (
            constant voltage_value_mV : in integer;
            constant current_value_uA : in integer
        ) is
        begin

            voltage_mV_in <=
                to_signed(
                    voltage_value_mV,
                    voltage_mV_in'length
                );

            current_uA_in <=
                to_signed(
                    current_value_uA,
                    current_uA_in'length
                );

            wait until falling_edge(clk_100mhz);

            sample_valid_in <= '1';

            wait until rising_edge(clk_100mhz);

            wait until falling_edge(clk_100mhz);

            sample_valid_in <= '0';

            wait for 20 ns;

        end procedure send_sample;


        ----------------------------------------------------------------
        -- Generate one 200-sample sinusoidal window
        ----------------------------------------------------------------
        procedure send_sine_window (

            constant voltage_peak_mV : in integer;
            constant current_peak_uA : in integer;
            constant phase_shift_deg : in real

        ) is

            variable angle_v : real;
            variable angle_i : real;

            variable voltage_real : real;
            variable current_real : real;

            variable voltage_integer : integer;
            variable current_integer : integer;

        begin

            for sample_index in 0 to WINDOW_SAMPLES - 1 loop

                angle_v :=
                    2.0 *
                    math_pi *
                    real(sample_index) /
                    real(WINDOW_SAMPLES);

                ------------------------------------------------------
                -- Positive phase shift means current lags voltage
                ------------------------------------------------------
                angle_i :=
                    angle_v
                    -
                    phase_shift_deg *
                    math_pi /
                    180.0;

                voltage_real :=
                    real(voltage_peak_mV) *
                    sin(angle_v);

                current_real :=
                    real(current_peak_uA) *
                    sin(angle_i);

                voltage_integer :=
                    integer(round(voltage_real));

                current_integer :=
                    integer(round(current_real));

                send_sample(
                    voltage_integer,
                    current_integer
                );

            end loop;

        end procedure send_sine_window;


        ----------------------------------------------------------------
        -- Check captured result
        ----------------------------------------------------------------
        procedure check_result (

            constant expected_p_mW  : in integer;
            constant expected_s_mVA : in integer;
            constant expected_pf    : in integer;

            constant p_tolerance  : in integer;
            constant s_tolerance  : in integer;
            constant pf_tolerance : in integer;

            constant test_name : in string

        ) is

            variable p_measured  : integer;
            variable s_measured  : integer;
            variable pf_measured : integer;

        begin

            ----------------------------------------------------------
            -- The monitor may already have captured the result.
            ----------------------------------------------------------
            if captured_valid /= '1' then
                wait until captured_valid = '1';
            end if;

            wait for 1 ns;

            p_measured :=
                to_integer(captured_active_power_mW);

            s_measured :=
                to_integer(captured_apparent_power_mVA);

            pf_measured :=
                to_integer(captured_power_factor_milli);


            ----------------------------------------------------------
            -- Active power
            ----------------------------------------------------------
            assert
                abs(p_measured - expected_p_mW)
                <= p_tolerance

                report
                    test_name &
                    " ACTIVE POWER FAIL: expected " &
                    integer'image(expected_p_mW) &
                    " mW, measured " &
                    integer'image(p_measured) &
                    " mW"

                severity error;


            ----------------------------------------------------------
            -- Apparent power
            ----------------------------------------------------------
            assert
                abs(s_measured - expected_s_mVA)
                <= s_tolerance

                report
                    test_name &
                    " APPARENT POWER FAIL: expected " &
                    integer'image(expected_s_mVA) &
                    " mVA, measured " &
                    integer'image(s_measured) &
                    " mVA"

                severity error;


            ----------------------------------------------------------
            -- Power factor
            ----------------------------------------------------------
            assert
                abs(pf_measured - expected_pf)
                <= pf_tolerance

                report
                    test_name &
                    " PF FAIL: expected " &
                    integer'image(expected_pf) &
                    ", measured " &
                    integer'image(pf_measured)

                severity error;


            ----------------------------------------------------------
            -- PASS
            ----------------------------------------------------------
            report
                test_name &
                " PASS: P=" &
                integer'image(p_measured) &
                " mW, S=" &
                integer'image(s_measured) &
                " mVA, PF=" &
                integer'image(pf_measured)

            severity note;

            wait for 30 ns;

        end procedure check_result;


        ----------------------------------------------------------------
        -- Reset between tests
        ----------------------------------------------------------------
        procedure reset_meter is
        begin

            reset <= '1';

            sample_valid_in <= '0';

            voltage_mV_in <= (others => '0');
            current_uA_in <= (others => '0');

            wait for 100 ns;

            reset <= '0';

            wait for 50 ns;

        end procedure reset_meter;


    begin


        ----------------------------------------------------------------
        -- TEST 1
        -- Unity PF
        ----------------------------------------------------------------
        reset_meter;

        voltage_rms_mV_in <= to_unsigned(229810, 32);
        current_rms_uA_in <= to_unsigned(707107, 32);

        send_sine_window(
            voltage_peak_mV => 325000,
            current_peak_uA => 1000000,
            phase_shift_deg => 0.0
        );

        check_result(
            expected_p_mW  => 162500,
            expected_s_mVA => 162500,
            expected_pf    => 1000,

            p_tolerance  => 5,
            s_tolerance  => 5,
            pf_tolerance => 1,

            test_name => "POWER TEST UNITY PF"
        );


        ----------------------------------------------------------------
        -- TEST 2
        -- 60 degree current lag
        -- PF = cos(60) = 0.5
        ----------------------------------------------------------------
        reset_meter;

        voltage_rms_mV_in <= to_unsigned(229810, 32);
        current_rms_uA_in <= to_unsigned(707107, 32);

        send_sine_window(
            voltage_peak_mV => 325000,
            current_peak_uA => 1000000,
            phase_shift_deg => 60.0
        );

        check_result(
            expected_p_mW  => 81250,
            expected_s_mVA => 162500,
            expected_pf    => 500,

            p_tolerance  => 10,
            s_tolerance  => 5,
            pf_tolerance => 2,

            test_name => "POWER TEST PF 0.5"
        );


        ----------------------------------------------------------------
        -- TEST 3
        -- 90 degree current lag
        -- Ideal reactive load
        ----------------------------------------------------------------
        reset_meter;

        voltage_rms_mV_in <= to_unsigned(229810, 32);
        current_rms_uA_in <= to_unsigned(707107, 32);

        send_sine_window(
            voltage_peak_mV => 325000,
            current_peak_uA => 1000000,
            phase_shift_deg => 90.0
        );

        check_result(
            expected_p_mW  => 0,
            expected_s_mVA => 162500,
            expected_pf    => 0,

            p_tolerance  => 10,
            s_tolerance  => 5,
            pf_tolerance => 2,

            test_name => "POWER TEST REACTIVE"
        );


        ----------------------------------------------------------------
        -- TEST 4
        -- 180 degree reversal
        ----------------------------------------------------------------
        reset_meter;

        voltage_rms_mV_in <= to_unsigned(229810, 32);
        current_rms_uA_in <= to_unsigned(707107, 32);

        send_sine_window(
            voltage_peak_mV => 325000,
            current_peak_uA => 1000000,
            phase_shift_deg => 180.0
        );

        check_result(
            expected_p_mW  => -162500,
            expected_s_mVA => 162500,
            expected_pf    => -1000,

            p_tolerance  => 5,
            s_tolerance  => 5,
            pf_tolerance => 1,

            test_name => "POWER TEST NEGATIVE"
        );


        ----------------------------------------------------------------
        -- TEST 5
        -- No load
        ----------------------------------------------------------------
        reset_meter;

        voltage_rms_mV_in <= to_unsigned(229810, 32);
        current_rms_uA_in <= to_unsigned(0, 32);

        send_sine_window(
            voltage_peak_mV => 325000,
            current_peak_uA => 0,
            phase_shift_deg => 0.0
        );

        check_result(
            expected_p_mW  => 0,
            expected_s_mVA => 0,
            expected_pf    => 0,

            p_tolerance  => 0,
            s_tolerance  => 0,
            pf_tolerance => 0,

            test_name => "POWER TEST NO LOAD"
        );


        ----------------------------------------------------------------
        -- Complete
        ----------------------------------------------------------------
        report
            "=============================================="
        severity note;

        report
            "POWER METER TESTS COMPLETED"
        severity note;

        report
            "=============================================="
        severity note;


        sim_done <= true;

        wait;


    end process;


end architecture simulation;