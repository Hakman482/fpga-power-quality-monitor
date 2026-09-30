library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_dual_rms is
end entity tb_dual_rms;


architecture simulation of tb_dual_rms is

    ------------------------------------------------------------------
    -- 100 MHz Nexys A7 clock
    ------------------------------------------------------------------

    constant CLK_PERIOD : time := 10 ns;


    ------------------------------------------------------------------
    -- DUT inputs
    ------------------------------------------------------------------

    signal clk_100mhz : std_logic := '0';
    signal reset      : std_logic := '1';

    signal voltage_mV_in : signed(31 downto 0)
                         := (others => '0');

    signal current_uA_in : signed(31 downto 0)
                         := (others => '0');

    signal sample_valid_in : std_logic := '0';


    ------------------------------------------------------------------
    -- DUT outputs
    ------------------------------------------------------------------

    signal voltage_rms_mV : unsigned(31 downto 0);
    signal current_rms_uA : unsigned(31 downto 0);

    signal rms_valid : std_logic;


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
    -- RMS DUT
    --
    -- Four samples are used for this unit test.
    -- Real project implementation uses 200 samples.
    ------------------------------------------------------------------

    DUT : entity work.dual_rms

        generic map (

            WINDOW_SAMPLES => 4

        )

        port map (

            clk_100mhz => clk_100mhz,
            reset      => reset,

            voltage_mV_in => voltage_mV_in,
            current_uA_in => current_uA_in,

            sample_valid_in => sample_valid_in,

            voltage_rms_mV => voltage_rms_mV,
            current_rms_uA => current_rms_uA,

            rms_valid => rms_valid

        );



    ------------------------------------------------------------------
    -- Stimulus and checker
    ------------------------------------------------------------------

    stimulus_process : process


        ----------------------------------------------------------------
        -- Send one synchronized V/I sample
        ----------------------------------------------------------------

        procedure send_sample (

            constant voltage_value : in integer;
            constant current_value : in integer

        ) is

        begin

            ------------------------------------------------------------
            -- Present sample
            ------------------------------------------------------------

            voltage_mV_in <=
                to_signed(voltage_value, voltage_mV_in'length);

            current_uA_in <=
                to_signed(current_value, current_uA_in'length);


            ------------------------------------------------------------
            -- Assert valid midway between FPGA rising edges
            ------------------------------------------------------------

            wait until falling_edge(clk_100mhz);

            sample_valid_in <= '1';


            ------------------------------------------------------------
            -- DUT captures sample at next rising edge
            ------------------------------------------------------------

            wait until rising_edge(clk_100mhz);

            wait for 1 ns;


            ------------------------------------------------------------
            -- Remove input valid at next falling edge
            ------------------------------------------------------------

            wait until falling_edge(clk_100mhz);

            sample_valid_in <= '0';


        end procedure send_sample;



        ----------------------------------------------------------------
        -- Check RMS result
        ----------------------------------------------------------------

        procedure check_result (

            constant expected_v : in integer;
            constant expected_i : in integer;
            constant test_name  : in string

        ) is

        begin


            ------------------------------------------------------------
            -- After the fourth sample, rms_valid may ALREADY be HIGH.
            --
            -- Only wait for a rising edge if it is not already HIGH.
            ------------------------------------------------------------

            if rms_valid /= '1' then

                wait until rising_edge(rms_valid);

            end if;


            wait for 1 ns;


            ------------------------------------------------------------
            -- Voltage RMS check
            ------------------------------------------------------------

            assert to_integer(voltage_rms_mV) = expected_v

                report
                    test_name &
                    " VOLTAGE RMS FAIL: expected " &
                    integer'image(expected_v) &
                    " mV, received " &
                    integer'image(to_integer(voltage_rms_mV)) &
                    " mV"

                severity error;


            ------------------------------------------------------------
            -- Current RMS check
            ------------------------------------------------------------

            assert to_integer(current_rms_uA) = expected_i

                report
                    test_name &
                    " CURRENT RMS FAIL: expected " &
                    integer'image(expected_i) &
                    " uA, received " &
                    integer'image(to_integer(current_rms_uA)) &
                    " uA"

                severity error;


            ------------------------------------------------------------
            -- PASS
            ------------------------------------------------------------

            report
                test_name &
                " PASS: Vrms=" &
                integer'image(to_integer(voltage_rms_mV)) &
                " mV, Irms=" &
                integer'image(to_integer(current_rms_uA)) &
                " uA"

            severity note;


            ------------------------------------------------------------
            -- Wait for output-valid pulse to finish
            ------------------------------------------------------------

            if rms_valid = '1' then

                wait until rms_valid = '0';

            end if;


            wait for 30 ns;


        end procedure check_result;



    begin


        ----------------------------------------------------------------
        -- RESET
        ----------------------------------------------------------------

        reset <= '1';

        sample_valid_in <= '0';

        voltage_mV_in <= (others => '0');
        current_uA_in <= (others => '0');

        wait for 100 ns;

        reset <= '0';

        wait for 50 ns;



        ----------------------------------------------------------------
        -- TEST 1
        -- Zero waveform
        ----------------------------------------------------------------

        send_sample(0, 0);
        send_sample(0, 0);
        send_sample(0, 0);
        send_sample(0, 0);

        check_result(

            expected_v => 0,
            expected_i => 0,

            test_name => "RMS TEST ZERO"

        );



        ----------------------------------------------------------------
        -- TEST 2
        -- Constant waveform
        ----------------------------------------------------------------

        send_sample(100000, 500000);
        send_sample(100000, 500000);
        send_sample(100000, 500000);
        send_sample(100000, 500000);

        check_result(

            expected_v => 100000,
            expected_i => 500000,

            test_name => "RMS TEST CONSTANT"

        );



        ----------------------------------------------------------------
        -- TEST 3
        -- Bipolar waveform
        ----------------------------------------------------------------

        send_sample( 100000,  250000);
        send_sample(-100000, -250000);
        send_sample( 100000,  250000);
        send_sample(-100000, -250000);

        check_result(

            expected_v => 100000,
            expected_i => 250000,

            test_name => "RMS TEST BIPOLAR"

        );



        ----------------------------------------------------------------
        -- TEST 4
        -- Known RMS:
        --
        -- Voltage:
        -- sqrt((3000² + 4000² + 0 + 0)/4)
        -- = 2500 mV
        --
        -- Current:
        -- sqrt((6000² + 8000² + 0 + 0)/4)
        -- = 5000 uA
        ----------------------------------------------------------------

        send_sample(3000, 6000);
        send_sample(4000, 8000);
        send_sample(0, 0);
        send_sample(0, 0);

        check_result(

            expected_v => 2500,
            expected_i => 5000,

            test_name => "RMS TEST PYTHAGOREAN"

        );



        ----------------------------------------------------------------
        -- TEST 5
        -- Negative constant waveform
        ----------------------------------------------------------------

        send_sample(-230000, -750000);
        send_sample(-230000, -750000);
        send_sample(-230000, -750000);
        send_sample(-230000, -750000);

        check_result(

            expected_v => 230000,
            expected_i => 750000,

            test_name => "RMS TEST NEGATIVE"

        );



        ----------------------------------------------------------------
        -- ALL TESTS COMPLETE
        ----------------------------------------------------------------

        report
            "=============================================="
        severity note;

        report
            "DUAL RMS TESTS COMPLETED"
        severity note;

        report
            "=============================================="
        severity note;


        sim_done <= true;

        wait;


    end process;


end architecture simulation;