library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

----------------------------------------------------------------------
-- Self-checking testbench for ADS8320 behavioural model
----------------------------------------------------------------------

entity tb_ads8320_model is
end entity tb_ads8320_model;


architecture simulation of tb_ads8320_model is

    ------------------------------------------------------------------
    -- ADS8320 interface signals
    ------------------------------------------------------------------

    signal cs_n      : std_logic := '1';
    signal dclock    : std_logic := '0';
    signal sample_in : std_logic_vector(15 downto 0) := (others => '0');
    signal dout      : std_logic;


    ------------------------------------------------------------------
    -- Simulation control
    ------------------------------------------------------------------

    signal sim_done : boolean := false;


    ------------------------------------------------------------------
    -- ADC serial clock
    --
    -- 2 MHz:
    --
    -- T = 1 / 2 MHz = 500 ns
    ------------------------------------------------------------------

    constant DCLOCK_PERIOD : time := 500 ns;


begin


    ------------------------------------------------------------------
    -- Instantiate ADS8320 behavioural model
    ------------------------------------------------------------------

    DUT : entity work.ads8320_model

        port map (

            cs_n      => cs_n,
            dclock    => dclock,
            sample_in => sample_in,
            dout      => dout

        );


    ------------------------------------------------------------------
    -- DCLOCK GENERATOR
    --
    -- Runs until sim_done becomes TRUE.
    ------------------------------------------------------------------

    dclock_process : process

    begin

        while not sim_done loop

            dclock <= '0';
            wait for DCLOCK_PERIOD / 2;

            dclock <= '1';
            wait for DCLOCK_PERIOD / 2;

        end loop;


        ----------------------------------------------------------------
        -- Leave clock LOW when simulation finishes
        ----------------------------------------------------------------

        dclock <= '0';

        wait;

    end process;



    ------------------------------------------------------------------
    -- STIMULUS + AUTOMATIC CHECKER
    ------------------------------------------------------------------

    stimulus_process : process


        ----------------------------------------------------------------
        -- Procedure: test_conversion
        --
        -- Performs one complete ADS8320 transaction.
        --
        -- It:
        --
        -- 1. Loads the desired simulated conversion result.
        -- 2. Pulls CS LOW safely between DCLOCK edges.
        -- 3. Checks the acquisition interval.
        -- 4. Checks the NULL bit.
        -- 5. Reads B15 ... B0.
        -- 6. Reconstructs the 16-bit result.
        -- 7. Compares received value against expected value.
        ----------------------------------------------------------------

        procedure test_conversion (

            constant expected_value : in std_logic_vector(15 downto 0);
            constant test_name      : in string

        ) is

            variable received_value : std_logic_vector(15 downto 0);

        begin


            ------------------------------------------------------------
            -- Put desired conversion result into ADC model
            ------------------------------------------------------------

            sample_in <= expected_value;


            ------------------------------------------------------------
            -- Wait for falling DCLOCK edge.
            --
            -- Then wait one-quarter period = 125 ns.
            --
            -- This places CS transition safely between clock edges.
            ------------------------------------------------------------

            wait until falling_edge(dclock);

            wait for DCLOCK_PERIOD / 4;


            ------------------------------------------------------------
            -- Start ADS8320 transaction
            ------------------------------------------------------------

            cs_n <= '0';


            ------------------------------------------------------------
            -- ACQUISITION / STARTUP
            --
            -- First four falling DCLOCK edges should leave DOUT
            -- high impedance.
            ------------------------------------------------------------

            for edge_number in 1 to 4 loop

                wait until falling_edge(dclock);

                --------------------------------------------------------
                -- Small delay allows ADS8320 model signal assignment
                -- to update before we inspect DOUT.
                --------------------------------------------------------

                wait for 1 ns;


                assert dout = 'Z'

                    report
                        test_name &
                        " FAIL: DOUT was not Z during acquisition."

                    severity error;

            end loop;



            ------------------------------------------------------------
            -- FIFTH FALLING EDGE
            --
            -- ADS8320 NULL bit should be 0.
            ------------------------------------------------------------

            wait until falling_edge(dclock);

            wait for 1 ns;


            assert dout = '0'

                report
                    test_name &
                    " FAIL: NULL bit was not 0."

                severity error;



            ------------------------------------------------------------
            -- NEXT 16 FALLING EDGES
            --
            -- Read conversion result:
            --
            -- B15 first
            -- ...
            -- B0 last
            ------------------------------------------------------------

            for bit_number in 15 downto 0 loop

                wait until falling_edge(dclock);

                wait for 1 ns;


                --------------------------------------------------------
                -- DOUT must now be valid binary data
                --------------------------------------------------------

                assert (dout = '0') or (dout = '1')

                    report
                        test_name &
                        " FAIL: Invalid DOUT state during data."

                    severity error;


                --------------------------------------------------------
                -- Store received serial bit
                --------------------------------------------------------

                received_value(bit_number) := dout;

            end loop;



            ------------------------------------------------------------
            -- Compare reconstructed 16-bit result with expected result
            ------------------------------------------------------------

            assert received_value = expected_value

                report
                    test_name &
                    " FAIL: Expected decimal value " &
                    integer'image(
                        to_integer(unsigned(expected_value))
                    ) &
                    ", received decimal value " &
                    integer'image(
                        to_integer(unsigned(received_value))
                    )

                severity error;



            ------------------------------------------------------------
            -- If previous assertion did not fail, report PASS
            ------------------------------------------------------------

            report
                test_name &
                " PASS: received decimal value " &
                integer'image(
                    to_integer(unsigned(received_value))
                )

            severity note;



            ------------------------------------------------------------
            -- End transaction.
            --
            -- We are currently just after a falling DCLOCK edge.
            --
            -- Wait 1/4 period so that CS rises safely between
            -- DCLOCK edges instead of coinciding with one.
            ------------------------------------------------------------

            wait for DCLOCK_PERIOD / 4;

            cs_n <= '1';


            ------------------------------------------------------------
            -- Allow idle time between ADC transactions
            ------------------------------------------------------------

            wait for 1 us;


            ------------------------------------------------------------
            -- DOUT should return to high impedance when CS is HIGH
            ------------------------------------------------------------

            assert dout = 'Z'

                report
                    test_name &
                    " FAIL: DOUT did not return to Z after CS went HIGH."

                severity error;


        end procedure test_conversion;



    begin


        ----------------------------------------------------------------
        -- INITIAL CONDITIONS
        ----------------------------------------------------------------

        cs_n      <= '1';
        sample_in <= (others => '0');


        ----------------------------------------------------------------
        -- Allow simulation to settle
        ----------------------------------------------------------------

        wait for 1 us;



        ----------------------------------------------------------------
        -- TEST 1
        --
        -- A735 =
        --
        -- 1010 0111 0011 0101
        ----------------------------------------------------------------

        test_conversion(

            expected_value => x"A735",
            test_name      => "TEST A735"

        );



        ----------------------------------------------------------------
        -- TEST 2
        --
        -- 1234 =
        --
        -- 0001 0010 0011 0100
        ----------------------------------------------------------------

        test_conversion(

            expected_value => x"1234",
            test_name      => "TEST 1234"

        );



        ----------------------------------------------------------------
        -- TEST 3
        --
        -- Minimum code
        ----------------------------------------------------------------

        test_conversion(

            expected_value => x"0000",
            test_name      => "TEST 0000"

        );



        ----------------------------------------------------------------
        -- TEST 4
        --
        -- Maximum code
        ----------------------------------------------------------------

        test_conversion(

            expected_value => x"FFFF",
            test_name      => "TEST FFFF"

        );



        ----------------------------------------------------------------
        -- If execution reaches this point, all four transactions
        -- have completed.
        ----------------------------------------------------------------

        report
            "=============================================="
        severity note;

        report
            "ADS8320 BEHAVIOURAL MODEL TESTS COMPLETED"
        severity note;

        report
            "=============================================="
        severity note;



        ----------------------------------------------------------------
        -- Stop DCLOCK generator
        ----------------------------------------------------------------

        sim_done <= true;


        ----------------------------------------------------------------
        -- No more stimulus
        ----------------------------------------------------------------

        wait;


    end process;


end architecture simulation;