library ieee;
use ieee.std_logic_1164.all;

----------------------------------------------------------------------
-- ADS8320 Behavioural Model
--
-- Simulation model for TI ADS8320 16-bit SAR ADC.
--
-- ADS8320 sequence represented:
--
--   CS falling edge -> start transaction
--
--   DCLOCK falling edges:
--
--      1
--      2          acquisition / conversion
--      3
--      4
--      5          NULL bit = 0
--      6          B15
--      7          B14
--      ...
--      20         B1
--      21         B0
--
-- Data changes on falling DCLOCK edges.
-- FPGA should normally sample DOUT on rising DCLOCK edges.
----------------------------------------------------------------------

entity ads8320_model is

    port (

        -- Active-low chip select
        cs_n      : in  std_logic;

        -- ADC serial clock
        dclock    : in  std_logic;

        -- Value which the simulated ADC should return
        sample_in : in  std_logic_vector(15 downto 0);

        -- Serial ADC output
        dout      : out std_logic

    );

end entity ads8320_model;


architecture behavioural of ads8320_model is

begin

    ------------------------------------------------------------------
    -- Entire ADC serial behaviour is contained in one process.
    ------------------------------------------------------------------

    process

        variable sample_latched : std_logic_vector(15 downto 0);
        variable edge_count     : integer := 0;
        variable bit_number     : integer;

    begin

        ----------------------------------------------------------------
        -- ADC is inactive while CS is HIGH.
        ----------------------------------------------------------------

        dout <= 'Z';

        ----------------------------------------------------------------
        -- Wait for falling edge of CS.
        -- This begins a new conversion.
        ----------------------------------------------------------------

        wait until falling_edge(cs_n);

        ----------------------------------------------------------------
        -- Capture the simulated ADC result.
        --
        -- sample_in represents the conversion value that would result
        -- from the analogue differential input.
        ----------------------------------------------------------------

        sample_latched := sample_in;

        edge_count := 0;


        ----------------------------------------------------------------
        -- Remain in this loop until FPGA raises CS again.
        ----------------------------------------------------------------

        while cs_n = '0' loop

            ----------------------------------------------------------------
            -- ADS8320 serial data changes on falling DCLOCK edges.
            ----------------------------------------------------------------

            wait until falling_edge(dclock) or cs_n = '1';


            --------------------------------------------------------------
            -- Abort immediately if CS was raised.
            --------------------------------------------------------------

            if cs_n = '1' then

                dout <= 'Z';

                exit;


            else

                edge_count := edge_count + 1;


                ----------------------------------------------------------
                -- DCLOCK falling edges 1 to 4
                --
                -- Acquisition / conversion interval.
                ----------------------------------------------------------

                if edge_count <= 4 then

                    dout <= 'Z';


                ----------------------------------------------------------
                -- 5th falling edge
                --
                -- NULL bit.
                ----------------------------------------------------------

                elsif edge_count = 5 then

                    dout <= '0';


                ----------------------------------------------------------
                -- Falling edges 6 through 21
                --
                -- 16-bit result, MSB first.
                ----------------------------------------------------------

                elsif edge_count >= 6 and edge_count <= 21 then

                    bit_number := 21 - edge_count;

                    dout <= sample_latched(bit_number);


                ----------------------------------------------------------
                -- If clocks continue, ADS8320 repeats data LSB first.
                ----------------------------------------------------------

                elsif edge_count >= 22 and edge_count <= 37 then

                    bit_number := edge_count - 22;

                    dout <= sample_latched(bit_number);


                ----------------------------------------------------------
                -- No more useful serial output.
                ----------------------------------------------------------

                else

                    dout <= 'Z';

                end if;

            end if;

        end loop;

    end process;

end architecture behavioural;