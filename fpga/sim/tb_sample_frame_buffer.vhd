library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_sample_frame_buffer is
end entity tb_sample_frame_buffer;


architecture simulation of tb_sample_frame_buffer is

    ------------------------------------------------------------------
    -- FPGA clock
    ------------------------------------------------------------------

    constant CLK_PERIOD : time := 10 ns;


    ------------------------------------------------------------------
    -- Frame size
    ------------------------------------------------------------------

    constant FRAME_SAMPLES : integer := 200;


    ------------------------------------------------------------------
    -- DUT inputs
    ------------------------------------------------------------------

    signal clk_100mhz :
        std_logic := '0';

    signal reset :
        std_logic := '1';


    signal voltage_mV_in :
        signed(31 downto 0) := (others => '0');

    signal current_uA_in :
        signed(31 downto 0) := (others => '0');

    signal sample_valid_in :
        std_logic := '0';


    ------------------------------------------------------------------
    -- DUT status
    ------------------------------------------------------------------

    signal frame_valid :
        std_logic;

    signal sample_count_out :
        unsigned(15 downto 0);


    ------------------------------------------------------------------
    -- DUT read interface
    ------------------------------------------------------------------

    signal read_index :
        unsigned(15 downto 0) := (others => '0');

    signal voltage_mV_out :
        signed(31 downto 0);

    signal current_uA_out :
        signed(31 downto 0);


    ------------------------------------------------------------------
    -- Monitor
    ------------------------------------------------------------------

    signal frame_valid_count :
        integer := 0;

    signal frame_seen :
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

    DUT : entity work.sample_frame_buffer

        generic map (

            FRAME_SAMPLES => FRAME_SAMPLES

        )

        port map (

            clk_100mhz => clk_100mhz,
            reset      => reset,

            voltage_mV_in => voltage_mV_in,
            current_uA_in => current_uA_in,

            sample_valid_in => sample_valid_in,

            frame_valid => frame_valid,

            sample_count_out => sample_count_out,

            read_index => read_index,

            voltage_mV_out => voltage_mV_out,
            current_uA_out => current_uA_out

        );



    ------------------------------------------------------------------
    -- Monitor frame_valid
    ------------------------------------------------------------------

    frame_monitor : process(clk_100mhz)
    begin

        if rising_edge(clk_100mhz) then

            if reset = '1' then

                frame_valid_count <= 0;
                frame_seen <= '0';

            else

                if frame_valid = '1' then

                    frame_valid_count <=
                        frame_valid_count + 1;

                    frame_seen <= '1';

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

            constant voltage_value : in integer;
            constant current_value : in integer

        ) is

        begin

            voltage_mV_in <=
                to_signed(
                    voltage_value,
                    voltage_mV_in'length
                );

            current_uA_in <=
                to_signed(
                    current_value,
                    current_uA_in'length
                );


            ------------------------------------------------------------
            -- Assert valid before rising edge
            ------------------------------------------------------------

            wait until falling_edge(clk_100mhz);

            sample_valid_in <= '1';


            ------------------------------------------------------------
            -- Sample captured here
            ------------------------------------------------------------

            wait until rising_edge(clk_100mhz);


            ------------------------------------------------------------
            -- Remove valid
            ------------------------------------------------------------

            wait until falling_edge(clk_100mhz);

            sample_valid_in <= '0';


            wait for 20 ns;

        end procedure send_sample;



        ----------------------------------------------------------------
        -- Read and verify one stored sample
        ----------------------------------------------------------------

        procedure check_sample (

            constant index_value :
                in integer;

            constant expected_voltage :
                in integer;

            constant expected_current :
                in integer

        ) is

        begin

            ------------------------------------------------------------
            -- Select memory index
            ------------------------------------------------------------

            read_index <=
                to_unsigned(
                    index_value,
                    read_index'length
                );


            ------------------------------------------------------------
            -- Asynchronous read: short delta/settling time
            ------------------------------------------------------------

            wait for 1 ns;


            ------------------------------------------------------------
            -- Verify voltage
            ------------------------------------------------------------

            assert
                to_integer(voltage_mV_out)
                =
                expected_voltage

                report
                    "FRAME BUFFER VOLTAGE FAIL AT INDEX " &
                    integer'image(index_value) &
                    ": expected " &
                    integer'image(expected_voltage) &
                    ", received " &
                    integer'image(
                        to_integer(voltage_mV_out)
                    )

                severity error;


            ------------------------------------------------------------
            -- Verify current
            ------------------------------------------------------------

            assert
                to_integer(current_uA_out)
                =
                expected_current

                report
                    "FRAME BUFFER CURRENT FAIL AT INDEX " &
                    integer'image(index_value) &
                    ": expected " &
                    integer'image(expected_current) &
                    ", received " &
                    integer'image(
                        to_integer(current_uA_out)
                    )

                severity error;

        end procedure check_sample;



    begin


        ----------------------------------------------------------------
        -- Reset
        ----------------------------------------------------------------

        reset <= '1';

        sample_valid_in <= '0';

        voltage_mV_in <= (others => '0');
        current_uA_in <= (others => '0');

        read_index <= (others => '0');

        wait for 100 ns;

        reset <= '0';

        wait for 50 ns;



        ----------------------------------------------------------------
        -- Fill one complete 200-sample frame
        --
        -- Use simple deterministic test values:
        --
        -- V[n] = 1000 + n
        --
        -- I[n] = -2000 - n
        ----------------------------------------------------------------

        for sample_index in 0 to FRAME_SAMPLES - 1 loop

            send_sample(

                voltage_value =>
                    1000 + sample_index,

                current_value =>
                    -2000 - sample_index

            );

        end loop;



        ----------------------------------------------------------------
        -- Allow frame_valid monitor to capture the pulse
        ----------------------------------------------------------------

        wait for 30 ns;



        ----------------------------------------------------------------
        -- Verify frame_valid occurred exactly once
        ----------------------------------------------------------------

        assert frame_seen = '1'

            report
                "FRAME BUFFER FAIL: frame_valid was never asserted"

            severity error;


        assert frame_valid_count = 1

            report
                "FRAME BUFFER FAIL: expected one frame_valid pulse, got " &
                integer'image(frame_valid_count)

            severity error;



        ----------------------------------------------------------------
        -- After frame completion, the buffer begins a new frame.
        --
        -- Therefore sample_count_out should be zero.
        ----------------------------------------------------------------

        assert
            to_integer(sample_count_out) = 0

            report
                "FRAME BUFFER FAIL: sample counter did not reset after frame"

            severity error;



        ----------------------------------------------------------------
        -- Read back all 200 samples
        ----------------------------------------------------------------

        for sample_index in 0 to FRAME_SAMPLES - 1 loop

            check_sample(

                index_value =>
                    sample_index,

                expected_voltage =>
                    1000 + sample_index,

                expected_current =>
                    -2000 - sample_index

            );

        end loop;



        ----------------------------------------------------------------
        -- PASS
        ----------------------------------------------------------------

        report
            "FRAME BUFFER ALL 200 SAMPLES PASS"
        severity note;


        report
            "FRAME VALID PULSE COUNT = " &
            integer'image(frame_valid_count)
        severity note;


        report
            "=============================================="
        severity note;


        report
            "SAMPLE FRAME BUFFER TESTS COMPLETED"
        severity note;


        report
            "=============================================="
        severity note;



        ----------------------------------------------------------------
        -- Stop simulation
        ----------------------------------------------------------------

        sim_done <= true;

        wait;


    end process;


end architecture simulation;