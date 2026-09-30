library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_sample_scale is
end entity tb_sample_scale;


architecture simulation of tb_sample_scale is

    ------------------------------------------------------------------
    -- 100 MHz FPGA clock
    ------------------------------------------------------------------

    constant CLK_PERIOD : time := 10 ns;


    ------------------------------------------------------------------
    -- DUT signals
    ------------------------------------------------------------------

    signal clk_100mhz : std_logic := '0';
    signal reset      : std_logic := '1';

    signal voltage_signed_in : signed(16 downto 0)
                             := (others => '0');

    signal current_signed_in : signed(16 downto 0)
                             := (others => '0');

    signal sample_valid_in : std_logic := '0';

    signal voltage_mV : signed(31 downto 0);
    signal current_uA : signed(31 downto 0);

    signal sample_valid_out : std_logic;


    ------------------------------------------------------------------
    -- Simulation control
    ------------------------------------------------------------------

    signal sim_done : boolean := false;


begin


    ------------------------------------------------------------------
    -- 100 MHz clock generator
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
    -- Instantiate updated scaling DUT
    ------------------------------------------------------------------

    DUT : entity work.sample_scale_v2

        port map (

            clk_100mhz => clk_100mhz,
            reset      => reset,

            voltage_signed_in => voltage_signed_in,
            current_signed_in => current_signed_in,

            sample_valid_in => sample_valid_in,

            voltage_mV => voltage_mV,
            current_uA => current_uA,

            sample_valid_out => sample_valid_out

        );



    ------------------------------------------------------------------
    -- Stimulus + self-checking process
    ------------------------------------------------------------------

    stimulus_process : process


        procedure check_scale (

            constant input_v      : in integer;
            constant input_i      : in integer;

            constant expected_mV  : in integer;
            constant expected_uA  : in integer;

            constant test_name    : in string

        ) is

        begin


            ------------------------------------------------------------
            -- Apply signed ADC-count inputs
            ------------------------------------------------------------

            voltage_signed_in <= to_signed(input_v, 17);
            current_signed_in <= to_signed(input_i, 17);


            ------------------------------------------------------------
            -- Assert valid on falling edge
            ------------------------------------------------------------

            wait until falling_edge(clk_100mhz);

            sample_valid_in <= '1';


            ------------------------------------------------------------
            -- Wait for scaled outputs
            ------------------------------------------------------------

            wait until rising_edge(sample_valid_out);

            wait for 1 ns;


            ------------------------------------------------------------
            -- Verify voltage
            ------------------------------------------------------------

            assert to_integer(voltage_mV) = expected_mV

                report
                    test_name &
                    " VOLTAGE FAIL: expected " &
                    integer'image(expected_mV) &
                    " mV, received " &
                    integer'image(to_integer(voltage_mV)) &
                    " mV"

                severity error;


            ------------------------------------------------------------
            -- Verify current
            ------------------------------------------------------------

            assert to_integer(current_uA) = expected_uA

                report
                    test_name &
                    " CURRENT FAIL: expected " &
                    integer'image(expected_uA) &
                    " uA, received " &
                    integer'image(to_integer(current_uA)) &
                    " uA"

                severity error;


            ------------------------------------------------------------
            -- PASS message
            ------------------------------------------------------------

            report
                test_name &
                " PASS: V=" &
                integer'image(to_integer(voltage_mV)) &
                " mV, I=" &
                integer'image(to_integer(current_uA)) &
                " uA"

            severity note;


            ------------------------------------------------------------
            -- Deassert valid
            ------------------------------------------------------------

            wait until falling_edge(clk_100mhz);

            sample_valid_in <= '0';


            ------------------------------------------------------------
            -- Wait for output-valid to fall
            ------------------------------------------------------------

            wait until sample_valid_out = '0';


            ------------------------------------------------------------
            -- Small delay between tests
            ------------------------------------------------------------

            wait for 50 ns;


        end procedure check_scale;



    begin


        ----------------------------------------------------------------
        -- Reset
        ----------------------------------------------------------------

        reset <= '1';

        sample_valid_in <= '0';

        voltage_signed_in <= (others => '0');
        current_signed_in <= (others => '0');

        wait for 100 ns;

        reset <= '0';

        wait for 50 ns;



        ----------------------------------------------------------------
        -- TEST 1
        -- Zero input
        ----------------------------------------------------------------

        check_scale(

            input_v      => 0,
            input_i      => 0,

            expected_mV  => 0,
            expected_uA  => 0,

            test_name    => "TEST ZERO"

        );



        ----------------------------------------------------------------
        -- TEST 2
        -- +1000 ADC counts
        ----------------------------------------------------------------

        check_scale(

            input_v      => 1000,
            input_i      => 1000,

            expected_mV  => 15297,
            expected_uA  => 47684,

            test_name    => "TEST +1000"

        );



        ----------------------------------------------------------------
        -- TEST 3
        -- -1000 ADC counts
        ----------------------------------------------------------------

        check_scale(

            input_v      => -1000,
            input_i      => -1000,

            expected_mV  => -15297,
            expected_uA  => -47684,

            test_name    => "TEST -1000"

        );



        ----------------------------------------------------------------
        -- TEST 4
        -- +10000 ADC counts
        ----------------------------------------------------------------

        check_scale(

            input_v      => 10000,
            input_i      => 10000,

            expected_mV  => 152970,
            expected_uA  => 476840,

            test_name    => "TEST +10000"

        );



        ----------------------------------------------------------------
        -- TEST 5
        -- Mixed polarity
        ----------------------------------------------------------------

        check_scale(

            input_v      => 8192,
            input_i      => -8192,

            expected_mV  => 125313,
            expected_uA  => -390627,

            test_name    => "TEST MIXED"

        );



        ----------------------------------------------------------------
        -- TEST 6
        -- Near-positive full-scale signed input
        ----------------------------------------------------------------

        check_scale(

            input_v      => 32767,
            input_i      => 32767,

            expected_mV  => 501236,
            expected_uA  => 1562461,

            test_name    => "TEST POSITIVE MAX"

        );



        ----------------------------------------------------------------
        -- TEST 7
        -- Negative full-scale signed input
        ----------------------------------------------------------------

        check_scale(

            input_v      => -32768,
            input_i      => -32768,

            expected_mV  => -501252,
            expected_uA  => -1562509,

            test_name    => "TEST NEGATIVE MAX"

        );



        ----------------------------------------------------------------
        -- All tests completed
        ----------------------------------------------------------------

        report
            "=============================================="
        severity note;

        report
            "SAMPLE SCALE TESTS COMPLETED"
        severity note;

        report
            "=============================================="
        severity note;


        sim_done <= true;

        wait;


    end process;


end architecture simulation;