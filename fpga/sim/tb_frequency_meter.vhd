library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity tb_frequency_meter is
end entity tb_frequency_meter;


architecture simulation of tb_frequency_meter is

    ------------------------------------------------------------------
    -- FPGA system clock
    ------------------------------------------------------------------

    constant CLK_PERIOD : time := 10 ns;


    ------------------------------------------------------------------
    -- Sampling interval
    --
    -- 10 kS/s = 100 us/sample
    ------------------------------------------------------------------

    constant SAMPLE_INTERVAL : time := 100 us;


    ------------------------------------------------------------------
    -- Synthetic voltage amplitude
    ------------------------------------------------------------------

    constant VOLTAGE_PEAK_MV : integer := 325000;


    ------------------------------------------------------------------
    -- DUT signals
    ------------------------------------------------------------------

    signal clk_100mhz : std_logic := '0';
    signal reset      : std_logic := '1';

    signal voltage_mV_in :
        signed(31 downto 0) := (others => '0');

    signal sample_valid_in :
        std_logic := '0';

    signal frequency_mHz :
        unsigned(31 downto 0);

    signal frequency_valid :
        std_logic;


    ------------------------------------------------------------------
    -- Captured frequency result
    --
    -- The monitor process stores the most recent valid measurement.
    ------------------------------------------------------------------

    signal captured_frequency_mHz :
        unsigned(31 downto 0) := (others => '0');

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
    -- Frequency-meter DUT
    ------------------------------------------------------------------

    DUT : entity work.frequency_meter

        generic map (

            SYS_CLK_HZ => 100_000_000

        )

        port map (

            clk_100mhz => clk_100mhz,
            reset      => reset,

            voltage_mV_in => voltage_mV_in,

            sample_valid_in => sample_valid_in,

            frequency_mHz => frequency_mHz,

            frequency_valid => frequency_valid

        );



    ------------------------------------------------------------------
    -- FREQUENCY RESULT MONITOR
    --
    -- This prevents the testbench from missing the short
    -- frequency_valid pulse.
    ------------------------------------------------------------------

    monitor_process : process(clk_100mhz)

    begin

        if rising_edge(clk_100mhz) then

            if reset = '1' then

                captured_frequency_mHz <= (others => '0');
                captured_valid <= '0';


            else

                if frequency_valid = '1' then

                    captured_frequency_mHz <= frequency_mHz;
                    captured_valid <= '1';

                end if;

            end if;

        end if;

    end process;



    ------------------------------------------------------------------
    -- Stimulus and automatic checker
    ------------------------------------------------------------------

    stimulus_process : process


        ----------------------------------------------------------------
        -- Send one voltage sample
        ----------------------------------------------------------------

        procedure send_sample (

            constant voltage_value : in integer

        ) is

        begin

            ------------------------------------------------------------
            -- Apply voltage sample
            ------------------------------------------------------------

            voltage_mV_in <=
                to_signed(
                    voltage_value,
                    voltage_mV_in'length
                );


            ------------------------------------------------------------
            -- Assert valid between FPGA rising edges
            ------------------------------------------------------------

            wait until falling_edge(clk_100mhz);

            sample_valid_in <= '1';


            ------------------------------------------------------------
            -- DUT captures on next rising edge
            ------------------------------------------------------------

            wait until rising_edge(clk_100mhz);


            ------------------------------------------------------------
            -- Remove valid on following falling edge
            ------------------------------------------------------------

            wait until falling_edge(clk_100mhz);

            sample_valid_in <= '0';


            ------------------------------------------------------------
            -- Finish the 100 us sample interval
            --
            -- 20 ns has already elapsed during the handshake.
            ------------------------------------------------------------

            wait for 99980 ns;


        end procedure send_sample;



        ----------------------------------------------------------------
        -- Generate synthetic sine waveform
        ----------------------------------------------------------------

        procedure send_sine_wave (

            constant frequency_hz : in real;
            constant cycles       : in integer

        ) is

            variable samples_per_test :
                integer;

            variable time_seconds :
                real;

            variable angle :
                real;

            variable sample_real :
                real;

            variable sample_integer :
                integer;

        begin


            ------------------------------------------------------------
            -- Number of samples needed for requested number of cycles
            ------------------------------------------------------------

            samples_per_test :=
                integer(
                    ceil(
                        real(cycles) *
                        10000.0 /
                        frequency_hz
                    )
                );


            ------------------------------------------------------------
            -- Generate samples
            ------------------------------------------------------------

            for sample_index in 0 to samples_per_test - 1 loop


                --------------------------------------------------------
                -- Sampling time
                --------------------------------------------------------

                time_seconds :=
                    real(sample_index) /
                    10000.0;


                --------------------------------------------------------
                -- Sine phase
                --------------------------------------------------------

                angle :=
                    2.0 *
                    math_pi *
                    frequency_hz *
                    time_seconds;


                --------------------------------------------------------
                -- Instantaneous voltage
                --------------------------------------------------------

                sample_real :=
                    real(VOLTAGE_PEAK_MV) *
                    sin(angle);


                sample_integer :=
                    integer(
                        round(sample_real)
                    );


                --------------------------------------------------------
                -- Send one sample
                --------------------------------------------------------

                send_sample(sample_integer);


            end loop;


        end procedure send_sine_wave;



        ----------------------------------------------------------------
        -- Check captured frequency
        ----------------------------------------------------------------

        procedure check_frequency (

            constant expected_mHz  : in integer;
            constant tolerance_mHz : in integer;
            constant test_name     : in string

        ) is

            variable measured :
                integer;

            variable error_value :
                integer;

        begin


            ------------------------------------------------------------
            -- Make sure at least one measurement was captured
            ------------------------------------------------------------

            if captured_valid /= '1' then

                wait until captured_valid = '1';

            end if;


            wait for 1 ns;


            ------------------------------------------------------------
            -- Read latest measurement
            ------------------------------------------------------------

            measured :=
                to_integer(
                    captured_frequency_mHz
                );


            error_value :=
                abs(
                    measured -
                    expected_mHz
                );


            ------------------------------------------------------------
            -- Check tolerance
            ------------------------------------------------------------

            assert error_value <= tolerance_mHz

                report
                    test_name &
                    " FAIL: expected approximately " &
                    integer'image(expected_mHz) &
                    " mHz, measured " &
                    integer'image(measured) &
                    " mHz"

                severity error;


            ------------------------------------------------------------
            -- PASS
            ------------------------------------------------------------

            report
                test_name &
                " PASS: measured frequency = " &
                integer'image(measured) &
                " mHz"

            severity note;


        end procedure check_frequency;



        ----------------------------------------------------------------
        -- Reset DUT between test frequencies
        ----------------------------------------------------------------

        procedure reset_meter is

        begin

            reset <= '1';

            sample_valid_in <= '0';

            voltage_mV_in <= (others => '0');

            wait for 200 ns;

            reset <= '0';

            wait for 100 us;

        end procedure reset_meter;



    begin


        ----------------------------------------------------------------
        -- INITIAL RESET
        ----------------------------------------------------------------

        reset_meter;



        ----------------------------------------------------------------
        -- TEST 1: 50 Hz
        ----------------------------------------------------------------

        send_sine_wave(

            frequency_hz => 50.0,
            cycles       => 3

        );


        check_frequency(

            expected_mHz  => 50000,
            tolerance_mHz => 300,

            test_name     => "FREQUENCY TEST 50HZ"

        );



        ----------------------------------------------------------------
        -- TEST 2: 49 Hz
        ----------------------------------------------------------------

        reset_meter;


        send_sine_wave(

            frequency_hz => 49.0,
            cycles       => 3

        );


        check_frequency(

            expected_mHz  => 49000,
            tolerance_mHz => 400,

            test_name     => "FREQUENCY TEST 49HZ"

        );



        ----------------------------------------------------------------
        -- TEST 3: 51 Hz
        ----------------------------------------------------------------

        reset_meter;


        send_sine_wave(

            frequency_hz => 51.0,
            cycles       => 3

        );


        check_frequency(

            expected_mHz  => 51000,
            tolerance_mHz => 400,

            test_name     => "FREQUENCY TEST 51HZ"

        );



        ----------------------------------------------------------------
        -- ALL TESTS COMPLETE
        ----------------------------------------------------------------

        report
            "=============================================="
        severity note;


        report
            "FREQUENCY METER TESTS COMPLETED"
        severity note;


        report
            "=============================================="
        severity note;


        sim_done <= true;

        wait;


    end process;


end architecture simulation;