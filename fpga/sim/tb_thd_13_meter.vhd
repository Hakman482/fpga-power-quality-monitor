library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity tb_thd_13_meter is
end entity tb_thd_13_meter;


architecture simulation of tb_thd_13_meter is


    ------------------------------------------------------------------
    -- FPGA clock
    ------------------------------------------------------------------

    constant CLK_PERIOD : time := 10 ns;


    ------------------------------------------------------------------
    -- DUT signals
    ------------------------------------------------------------------

    signal clk_100mhz :
        std_logic := '0';

    signal reset :
        std_logic := '1';


    signal voltage_fund_mag_sq :
        unsigned(79 downto 0) := (others => '0');

    signal voltage_3rd_mag_sq :
        unsigned(79 downto 0) := (others => '0');

    signal current_fund_mag_sq :
        unsigned(79 downto 0) := (others => '0');

    signal current_3rd_mag_sq :
        unsigned(79 downto 0) := (others => '0');


    signal harmonic_valid_in :
        std_logic := '0';


    signal voltage_thd_x100 :
        unsigned(15 downto 0);

    signal current_thd_x100 :
        unsigned(15 downto 0);

    signal thd_valid :
        std_logic;


    ------------------------------------------------------------------
    -- Captured outputs
    ------------------------------------------------------------------

    signal captured_voltage_thd :
        unsigned(15 downto 0) := (others => '0');

    signal captured_current_thd :
        unsigned(15 downto 0) := (others => '0');

    signal captured_valid :
        std_logic := '0';


    ------------------------------------------------------------------
    -- Simulation control
    ------------------------------------------------------------------

    signal sim_done :
        boolean := false;


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

    DUT : entity work.thd_13_meter

        port map (

            clk_100mhz =>
                clk_100mhz,

            reset =>
                reset,


            voltage_fund_mag_sq =>
                voltage_fund_mag_sq,

            voltage_3rd_mag_sq =>
                voltage_3rd_mag_sq,

            current_fund_mag_sq =>
                current_fund_mag_sq,

            current_3rd_mag_sq =>
                current_3rd_mag_sq,


            harmonic_valid_in =>
                harmonic_valid_in,


            voltage_thd_x100 =>
                voltage_thd_x100,

            current_thd_x100 =>
                current_thd_x100,


            thd_valid =>
                thd_valid

        );



    ------------------------------------------------------------------
    -- Capture short thd_valid pulse
    ------------------------------------------------------------------

    monitor_process : process(clk_100mhz)

    begin

        if rising_edge(clk_100mhz) then

            if reset = '1' then

                captured_voltage_thd <=
                    (others => '0');

                captured_current_thd <=
                    (others => '0');

                captured_valid <= '0';


            elsif thd_valid = '1' then

                captured_voltage_thd <=
                    voltage_thd_x100;

                captured_current_thd <=
                    current_thd_x100;

                captured_valid <= '1';

            end if;

        end if;

    end process;



    ------------------------------------------------------------------
    -- Stimulus
    ------------------------------------------------------------------

    stimulus_process : process


        ----------------------------------------------------------------
        -- Reset DUT
        ----------------------------------------------------------------

        procedure reset_meter is

        begin

            reset <= '1';

            harmonic_valid_in <= '0';

            voltage_fund_mag_sq <=
                (others => '0');

            voltage_3rd_mag_sq <=
                (others => '0');

            current_fund_mag_sq <=
                (others => '0');

            current_3rd_mag_sq <=
                (others => '0');

            wait for 100 ns;

            reset <= '0';

            wait for 50 ns;

        end procedure reset_meter;



        ----------------------------------------------------------------
        -- Trigger one THD calculation
        ----------------------------------------------------------------

        procedure trigger_calculation is

        begin

            wait until falling_edge(clk_100mhz);

            harmonic_valid_in <= '1';


            wait until rising_edge(clk_100mhz);


            wait until falling_edge(clk_100mhz);

            harmonic_valid_in <= '0';


        end procedure trigger_calculation;



        ----------------------------------------------------------------
        -- Check result
        ----------------------------------------------------------------

        procedure check_result (

            constant expected_voltage :
                in integer;

            constant expected_current :
                in integer;

            constant tolerance :
                in integer;

            constant test_name :
                in string

        ) is

            variable measured_v :
                integer;

            variable measured_i :
                integer;

        begin


            ----------------------------------------------------------
            -- Result may already have been captured.
            ----------------------------------------------------------

            if captured_valid /= '1' then

                wait until captured_valid = '1';

            end if;


            wait for 1 ns;


            measured_v :=
                to_integer(
                    captured_voltage_thd
                );


            measured_i :=
                to_integer(
                    captured_current_thd
                );


            ----------------------------------------------------------
            -- Voltage check
            ----------------------------------------------------------

            assert
                abs(
                    measured_v -
                    expected_voltage
                )
                <= tolerance

                report
                    test_name &
                    " VOLTAGE THD FAIL: expected " &
                    integer'image(expected_voltage) &
                    ", measured " &
                    integer'image(measured_v)

                severity error;


            ----------------------------------------------------------
            -- Current check
            ----------------------------------------------------------

            assert
                abs(
                    measured_i -
                    expected_current
                )
                <= tolerance

                report
                    test_name &
                    " CURRENT THD FAIL: expected " &
                    integer'image(expected_current) &
                    ", measured " &
                    integer'image(measured_i)

                severity error;


            ----------------------------------------------------------
            -- PASS
            ----------------------------------------------------------

            report
                test_name &
                " PASS: VTHD=" &
                integer'image(measured_v) &
                ", ITHD=" &
                integer'image(measured_i)

            severity note;


            wait for 30 ns;

        end procedure check_result;



    begin


        ----------------------------------------------------------------
        -- TEST 1
        --
        -- Voltage:
        --
        -- V3² / V1² = 0.01
        --
        -- therefore:
        --
        -- V3/V1 = 0.10
        --
        -- THD = 10.00%
        --
        -- output = 1000
        --
        --
        -- Current:
        --
        -- I3² / I1² = 0.04
        --
        -- I3/I1 = 0.20
        --
        -- THD = 20.00%
        --
        -- output = 2000
        ----------------------------------------------------------------

        reset_meter;


        --------------------------------------------------------------
        -- Arbitrary fundamental squared magnitude = 1,000,000
        --------------------------------------------------------------

        voltage_fund_mag_sq <=
            to_unsigned(
                1_000_000,
                80
            );

        --------------------------------------------------------------
        -- 1% of fundamental squared
        --------------------------------------------------------------

        voltage_3rd_mag_sq <=
            to_unsigned(
                10_000,
                80
            );


        --------------------------------------------------------------
        -- Current fundamental squared
        --------------------------------------------------------------

        current_fund_mag_sq <=
            to_unsigned(
                1_000_000,
                80
            );

        --------------------------------------------------------------
        -- 4% of fundamental squared
        --------------------------------------------------------------

        current_3rd_mag_sq <=
            to_unsigned(
                40_000,
                80
            );


        trigger_calculation;


        check_result(

            expected_voltage =>
                1000,

            expected_current =>
                2000,

            tolerance =>
                1,

            test_name =>
                "THD TEST 10PCT / 20PCT"

        );



        ----------------------------------------------------------------
        -- TEST 2
        --
        -- Zero harmonic content
        --
        -- THD = 0
        ----------------------------------------------------------------

        reset_meter;


        voltage_fund_mag_sq <=
            to_unsigned(
                2_000_000,
                80
            );

        voltage_3rd_mag_sq <=
            to_unsigned(
                0,
                80
            );


        current_fund_mag_sq <=
            to_unsigned(
                3_000_000,
                80
            );

        current_3rd_mag_sq <=
            to_unsigned(
                0,
                80
            );


        trigger_calculation;


        check_result(

            expected_voltage =>
                0,

            expected_current =>
                0,

            tolerance =>
                0,

            test_name =>
                "THD TEST ZERO"

        );



        ----------------------------------------------------------------
        -- TEST 3
        --
        -- 5% voltage THD
        --
        -- ratio = 0.05
        --
        -- squared ratio = 0.0025
        --
        -- fundamental² = 4,000,000
        --
        -- harmonic² = 10,000
        --
        --
        -- Current = 25%
        --
        -- squared ratio = 0.0625
        --
        -- fundamental² = 4,000,000
        --
        -- harmonic² = 250,000
        ----------------------------------------------------------------

        reset_meter;


        voltage_fund_mag_sq <=
            to_unsigned(
                4_000_000,
                80
            );

        voltage_3rd_mag_sq <=
            to_unsigned(
                10_000,
                80
            );


        current_fund_mag_sq <=
            to_unsigned(
                4_000_000,
                80
            );

        current_3rd_mag_sq <=
            to_unsigned(
                250_000,
                80
            );


        trigger_calculation;


        check_result(

            expected_voltage =>
                500,

            expected_current =>
                2500,

            tolerance =>
                1,

            test_name =>
                "THD TEST 5PCT / 25PCT"

        );



        ----------------------------------------------------------------
        -- TEST 4
        --
        -- Zero fundamental.
        --
        -- Current thd_meter implementation intentionally returns
        -- zero instead of dividing by zero.
        ----------------------------------------------------------------

        reset_meter;


        voltage_fund_mag_sq <=
            to_unsigned(
                0,
                80
            );

        voltage_3rd_mag_sq <=
            to_unsigned(
                1000,
                80
            );


        current_fund_mag_sq <=
            to_unsigned(
                0,
                80
            );

        current_3rd_mag_sq <=
            to_unsigned(
                1000,
                80
            );


        trigger_calculation;


        check_result(

            expected_voltage =>
                0,

            expected_current =>
                0,

            tolerance =>
                0,

            test_name =>
                "THD TEST ZERO FUNDAMENTAL"

        );



        ----------------------------------------------------------------
        -- All tests complete
        ----------------------------------------------------------------

        report
            "=============================================="
        severity note;


        report
            "THD 1/3 METER TESTS COMPLETED"
        severity note;


        report
            "=============================================="
        severity note;


        sim_done <= true;

        wait;


    end process;


end architecture simulation;