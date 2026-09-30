library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_dual_adc_if is
end entity tb_dual_adc_if;


architecture simulation of tb_dual_adc_if is

    ------------------------------------------------------------------
    -- 100 MHz FPGA clock
    ------------------------------------------------------------------

    constant CLK_PERIOD : time := 10 ns;


    ------------------------------------------------------------------
    -- FPGA signals
    ------------------------------------------------------------------

    signal clk_100mhz : std_logic := '0';
    signal reset      : std_logic := '1';

    signal adc_cs_n   : std_logic;
    signal adc_dclock : std_logic;

    signal adc_dout_v : std_logic;
    signal adc_dout_i : std_logic;

    signal voltage_data : std_logic_vector(15 downto 0);
    signal current_data : std_logic_vector(15 downto 0);

    signal sample_valid : std_logic;


    ------------------------------------------------------------------
    -- Values returned by behavioural ADC models
    ------------------------------------------------------------------

    signal sample_v : std_logic_vector(15 downto 0)
                    := (others => '0');

    signal sample_i : std_logic_vector(15 downto 0)
                    := (others => '0');


    ------------------------------------------------------------------
    -- Simulation termination
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
    -- Dual FPGA ADC interface
    ------------------------------------------------------------------

    UUT : entity work.dual_adc_if

        port map (

            clk_100mhz => clk_100mhz,
            reset      => reset,

            adc_dout_v => adc_dout_v,
            adc_dout_i => adc_dout_i,

            adc_cs_n   => adc_cs_n,
            adc_dclock => adc_dclock,

            voltage_data => voltage_data,
            current_data => current_data,

            sample_valid => sample_valid

        );



    ------------------------------------------------------------------
    -- Voltage ADS8320 behavioural model
    ------------------------------------------------------------------

    ADC_VOLTAGE : entity work.ads8320_model

        port map (

            cs_n      => adc_cs_n,
            dclock    => adc_dclock,

            sample_in => sample_v,

            dout      => adc_dout_v

        );



    ------------------------------------------------------------------
    -- Current ADS8320 behavioural model
    ------------------------------------------------------------------

    ADC_CURRENT : entity work.ads8320_model

        port map (

            cs_n      => adc_cs_n,
            dclock    => adc_dclock,

            sample_in => sample_i,

            dout      => adc_dout_i

        );



    ------------------------------------------------------------------
    -- Stimulus and automatic checker
    ------------------------------------------------------------------

    stimulus_process : process


        procedure check_dual_sample (

            constant expected_v : in std_logic_vector(15 downto 0);
            constant expected_i : in std_logic_vector(15 downto 0);
            constant test_name  : in string

        ) is

        begin


            ------------------------------------------------------------
            -- Wait until ADCs are deselected
            ------------------------------------------------------------

            if adc_cs_n /= '1' then
                wait until rising_edge(adc_cs_n);
            end if;


            ------------------------------------------------------------
            -- Supply values for next simultaneous conversion
            ------------------------------------------------------------

            sample_v <= expected_v;
            sample_i <= expected_i;


            ------------------------------------------------------------
            -- Allow values to settle
            ------------------------------------------------------------

            wait for 20 ns;


            ------------------------------------------------------------
            -- Wait for shared CS falling edge
            ------------------------------------------------------------

            wait until falling_edge(adc_cs_n);


            ------------------------------------------------------------
            -- Wait for FPGA to reconstruct both values
            ------------------------------------------------------------

            wait until rising_edge(sample_valid);

            wait for 1 ns;


            ------------------------------------------------------------
            -- Check voltage channel
            ------------------------------------------------------------

            assert voltage_data = expected_v

                report
                    test_name &
                    " VOLTAGE FAIL: expected " &
                    integer'image(to_integer(unsigned(expected_v))) &
                    ", received " &
                    integer'image(to_integer(unsigned(voltage_data)))

                severity error;



            ------------------------------------------------------------
            -- Check current channel
            ------------------------------------------------------------

            assert current_data = expected_i

                report
                    test_name &
                    " CURRENT FAIL: expected " &
                    integer'image(to_integer(unsigned(expected_i))) &
                    ", received " &
                    integer'image(to_integer(unsigned(current_data)))

                severity error;



            ------------------------------------------------------------
            -- PASS report
            ------------------------------------------------------------

            report
                test_name &
                " PASS: V=" &
                integer'image(to_integer(unsigned(voltage_data))) &
                " I=" &
                integer'image(to_integer(unsigned(current_data)))

            severity note;



            ------------------------------------------------------------
            -- Wait for valid pulse to finish
            ------------------------------------------------------------

            if sample_valid = '1' then
                wait until sample_valid = '0';
            end if;


        end procedure check_dual_sample;



    begin


        ----------------------------------------------------------------
        -- Reset
        ----------------------------------------------------------------

        reset <= '1';

        sample_v <= (others => '0');
        sample_i <= (others => '0');

        wait for 200 ns;

        reset <= '0';



        ----------------------------------------------------------------
        -- TEST 1
        ----------------------------------------------------------------

        check_dual_sample(

            expected_v => x"A735",
            expected_i => x"1234",
            test_name  => "DUAL TEST 1"

        );



        ----------------------------------------------------------------
        -- TEST 2
        ----------------------------------------------------------------

        check_dual_sample(

            expected_v => x"0000",
            expected_i => x"FFFF",
            test_name  => "DUAL TEST 2"

        );



        ----------------------------------------------------------------
        -- TEST 3
        ----------------------------------------------------------------

        check_dual_sample(

            expected_v => x"AAAA",
            expected_i => x"5555",
            test_name  => "DUAL TEST 3"

        );



        ----------------------------------------------------------------
        -- TEST 4
        ----------------------------------------------------------------

        check_dual_sample(

            expected_v => x"1357",
            expected_i => x"2468",
            test_name  => "DUAL TEST 4"

        );



        ----------------------------------------------------------------
        -- TEST 5
        ----------------------------------------------------------------

        check_dual_sample(

            expected_v => x"8000",
            expected_i => x"7FFF",
            test_name  => "DUAL TEST 5"

        );



        ----------------------------------------------------------------
        -- Completed
        ----------------------------------------------------------------

        report
            "=============================================="
        severity note;

        report
            "DUAL ADS8320 INTERFACE TESTS COMPLETED"
        severity note;

        report
            "=============================================="
        severity note;


        sim_done <= true;

        wait;


    end process;


end architecture simulation;