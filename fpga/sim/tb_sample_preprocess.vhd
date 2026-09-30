library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_sample_preprocess is
end entity tb_sample_preprocess;


architecture simulation of tb_sample_preprocess is

    ------------------------------------------------------------------
    -- 100 MHz FPGA clock
    ------------------------------------------------------------------

    constant CLK_PERIOD : time := 10 ns;


    ------------------------------------------------------------------
    -- DUT signals
    ------------------------------------------------------------------

    signal clk_100mhz : std_logic := '0';
    signal reset      : std_logic := '1';

    signal voltage_raw : std_logic_vector(15 downto 0)
                       := (others => '0');

    signal current_raw : std_logic_vector(15 downto 0)
                       := (others => '0');

    signal sample_valid_in : std_logic := '0';

    signal voltage_signed : signed(16 downto 0);
    signal current_signed : signed(16 downto 0);

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
    -- Instantiate sample preprocessing DUT
    ------------------------------------------------------------------

    DUT : entity work.sample_preprocess

        port map (

            clk_100mhz => clk_100mhz,
            reset      => reset,

            voltage_raw => voltage_raw,
            current_raw => current_raw,

            sample_valid_in => sample_valid_in,

            voltage_signed => voltage_signed,
            current_signed => current_signed,

            sample_valid_out => sample_valid_out

        );



    ------------------------------------------------------------------
    -- Stimulus and self-checking process
    ------------------------------------------------------------------

    stimulus_process : process


        ----------------------------------------------------------------
        -- Procedure:
        -- Apply one raw voltage/current sample pair and verify
        -- midpoint subtraction.
        ----------------------------------------------------------------

        procedure check_sample (

            constant raw_v      : in std_logic_vector(15 downto 0);
            constant raw_i      : in std_logic_vector(15 downto 0);

            constant expected_v : in integer;
            constant expected_i : in integer;

            constant test_name  : in string

        ) is

        begin


            ------------------------------------------------------------
            -- Apply raw ADC values
            ------------------------------------------------------------

            voltage_raw <= raw_v;
            current_raw <= raw_i;


            ------------------------------------------------------------
            -- Assert input-valid on a falling FPGA clock edge.
            --
            -- This gives the signals half a clock cycle to settle
            -- before the DUT sees them at the next rising edge.
            ------------------------------------------------------------

            wait until falling_edge(clk_100mhz);

            sample_valid_in <= '1';


            ------------------------------------------------------------
            -- DUT processes the values at the next rising FPGA edge.
            --
            -- sample_valid_out is asserted by the DUT when the signed
            -- outputs have been generated.
            ------------------------------------------------------------

            wait until rising_edge(sample_valid_out);

            wait for 1 ns;


            ------------------------------------------------------------
            -- Check voltage output
            ------------------------------------------------------------

            assert to_integer(voltage_signed) = expected_v

                report
                    test_name &
                    " VOLTAGE FAIL: expected " &
                    integer'image(expected_v) &
                    ", received " &
                    integer'image(to_integer(voltage_signed))

                severity error;


            ------------------------------------------------------------
            -- Check current output
            ------------------------------------------------------------

            assert to_integer(current_signed) = expected_i

                report
                    test_name &
                    " CURRENT FAIL: expected " &
                    integer'image(expected_i) &
                    ", received " &
                    integer'image(to_integer(current_signed))

                severity error;


            ------------------------------------------------------------
            -- PASS message
            ------------------------------------------------------------

            report
                test_name &
                " PASS: V=" &
                integer'image(to_integer(voltage_signed)) &
                " I=" &
                integer'image(to_integer(current_signed))

            severity note;


            ------------------------------------------------------------
            -- Deassert sample_valid_in on the next falling FPGA edge
            ------------------------------------------------------------

            wait until falling_edge(clk_100mhz);

            sample_valid_in <= '0';


            ------------------------------------------------------------
            -- Wait until DUT drops sample_valid_out
            ------------------------------------------------------------

            wait until sample_valid_out = '0';


            ------------------------------------------------------------
            -- Small separation between tests
            ------------------------------------------------------------

            wait for 50 ns;


        end procedure check_sample;



    begin


        ----------------------------------------------------------------
        -- Initial conditions / reset
        ----------------------------------------------------------------

        reset <= '1';

        sample_valid_in <= '0';

        voltage_raw <= (others => '0');
        current_raw <= (others => '0');


        wait for 100 ns;


        ----------------------------------------------------------------
        -- Release reset
        ----------------------------------------------------------------

        reset <= '0';

        wait for 50 ns;



        ----------------------------------------------------------------
        -- TEST 1
        --
        -- Midscale:
        --
        -- 0x8000 - 0x8000 = 0
        ----------------------------------------------------------------

        check_sample(

            raw_v      => x"8000",
            raw_i      => x"8000",

            expected_v => 0,
            expected_i => 0,

            test_name  => "TEST MIDSCALE"

        );



        ----------------------------------------------------------------
        -- TEST 2
        --
        -- Minimum code:
        --
        -- 0x0000 - 0x8000 = -32768
        ----------------------------------------------------------------

        check_sample(

            raw_v      => x"0000",
            raw_i      => x"0000",

            expected_v => -32768,
            expected_i => -32768,

            test_name  => "TEST MINIMUM"

        );



        ----------------------------------------------------------------
        -- TEST 3
        --
        -- Maximum code:
        --
        -- 0xFFFF - 0x8000 = +32767
        ----------------------------------------------------------------

        check_sample(

            raw_v      => x"FFFF",
            raw_i      => x"FFFF",

            expected_v => 32767,
            expected_i => 32767,

            test_name  => "TEST MAXIMUM"

        );



        ----------------------------------------------------------------
        -- TEST 4
        --
        -- Quarter scale:
        --
        -- 0x4000 = 16384
        --
        -- 16384 - 32768 = -16384
        ----------------------------------------------------------------

        check_sample(

            raw_v      => x"4000",
            raw_i      => x"4000",

            expected_v => -16384,
            expected_i => -16384,

            test_name  => "TEST QUARTER"

        );



        ----------------------------------------------------------------
        -- TEST 5
        --
        -- Three-quarter scale:
        --
        -- 0xC000 = 49152
        --
        -- 49152 - 32768 = +16384
        ----------------------------------------------------------------

        check_sample(

            raw_v      => x"C000",
            raw_i      => x"C000",

            expected_v => 16384,
            expected_i => 16384,

            test_name  => "TEST THREE-QUARTER"

        );



        ----------------------------------------------------------------
        -- TEST 6
        --
        -- Mixed positive and negative values
        --
        -- Voltage:
        -- 0xA000 = 40960
        -- 40960 - 32768 = +8192
        --
        -- Current:
        -- 0x6000 = 24576
        -- 24576 - 32768 = -8192
        ----------------------------------------------------------------

        check_sample(

            raw_v      => x"A000",
            raw_i      => x"6000",

            expected_v => 8192,
            expected_i => -8192,

            test_name  => "TEST MIXED"

        );



        ----------------------------------------------------------------
        -- All tests complete
        ----------------------------------------------------------------

        report
            "=============================================="
        severity note;

        report
            "SAMPLE PREPROCESS TESTS COMPLETED"
        severity note;

        report
            "=============================================="
        severity note;


        ----------------------------------------------------------------
        -- Stop system clock
        ----------------------------------------------------------------

        sim_done <= true;


        wait;


    end process;


end architecture simulation;