library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity dual_adc_if is

    generic (

        ----------------------------------------------------------------
        -- Nexys A7 system clock frequency
        ----------------------------------------------------------------
        SYS_CLK_HZ     : integer := 100_000_000;

        ----------------------------------------------------------------
        -- ADS8320 serial clock frequency
        ----------------------------------------------------------------
        ADC_DCLOCK_HZ  : integer := 2_000_000;

        ----------------------------------------------------------------
        -- Required synchronized sampling rate
        ----------------------------------------------------------------
        SAMPLE_RATE_HZ : integer := 10_000

    );

    port (

        ----------------------------------------------------------------
        -- FPGA system signals
        ----------------------------------------------------------------
        clk_100mhz : in  std_logic;
        reset      : in  std_logic;


        ----------------------------------------------------------------
        -- Serial outputs from the two ADS8320 ADCs
        ----------------------------------------------------------------
        adc_dout_v : in  std_logic;
        adc_dout_i : in  std_logic;


        ----------------------------------------------------------------
        -- Shared ADS8320 control outputs
        ----------------------------------------------------------------
        adc_cs_n   : out std_logic;
        adc_dclock : out std_logic;


        ----------------------------------------------------------------
        -- Synchronized 16-bit conversion results
        ----------------------------------------------------------------
        voltage_data : out std_logic_vector(15 downto 0);
        current_data : out std_logic_vector(15 downto 0);


        ----------------------------------------------------------------
        -- One 100 MHz clock pulse when both samples are ready
        ----------------------------------------------------------------
        sample_valid : out std_logic

    );

end entity dual_adc_if;



architecture rtl of dual_adc_if is


    --------------------------------------------------------------------
    -- ADC DCLOCK divider
    --
    -- With defaults:
    --
    -- 100 MHz / (2 × 2 MHz) = 25
    --------------------------------------------------------------------

    constant DCLOCK_DIVIDER : integer :=
        SYS_CLK_HZ / (2 * ADC_DCLOCK_HZ);


    --------------------------------------------------------------------
    -- Number of FPGA clocks between conversion starts
    --
    -- With defaults:
    --
    -- 100 MHz / 10 kHz = 10,000 clocks
    --------------------------------------------------------------------

    constant SAMPLE_PERIOD_CLKS : integer :=
        SYS_CLK_HZ / SAMPLE_RATE_HZ;


    --------------------------------------------------------------------
    -- ADC serial clock divider
    --------------------------------------------------------------------

    signal clk_div_count :
        integer range 0 to DCLOCK_DIVIDER - 1 := 0;

    signal dclock_int : std_logic := '0';

    signal dclock_rising  : std_logic := '0';
    signal dclock_falling : std_logic := '0';


    --------------------------------------------------------------------
    -- 10 kS/s sample-rate timer
    --------------------------------------------------------------------

    signal sample_count :
        integer range 0 to SAMPLE_PERIOD_CLKS - 1 := 0;

    signal sample_tick : std_logic := '0';


    --------------------------------------------------------------------
    -- ADS8320 controller state machine
    --------------------------------------------------------------------

    type state_type is (

        IDLE,
        ACQUIRE,
        NULL_BIT,
        WAIT_B15,
        READ_DATA,
        COMPLETE

    );

    signal state : state_type := IDLE;


    --------------------------------------------------------------------
    -- Startup/acquisition edge counter
    --------------------------------------------------------------------

    signal startup_count : integer range 0 to 3 := 0;


    --------------------------------------------------------------------
    -- Data bit counter
    --------------------------------------------------------------------

    signal bit_count : integer range 0 to 15 := 15;


    --------------------------------------------------------------------
    -- Separate receive registers
    --------------------------------------------------------------------

    signal shift_reg_v :
        std_logic_vector(15 downto 0) := (others => '0');

    signal shift_reg_i :
        std_logic_vector(15 downto 0) := (others => '0');


    --------------------------------------------------------------------
    -- Internal active-low chip-select
    --------------------------------------------------------------------

    signal cs_n_int : std_logic := '1';


begin


    --------------------------------------------------------------------
    -- Output assignments
    --------------------------------------------------------------------

    adc_cs_n   <= cs_n_int;
    adc_dclock <= dclock_int;



    --------------------------------------------------------------------
    -- SAMPLE RATE GENERATOR
    --
    -- Generates one sample_tick every 100 us when SAMPLE_RATE_HZ
    -- is 10 kHz.
    --------------------------------------------------------------------

    sample_rate_generator : process(clk_100mhz)

    begin

        if rising_edge(clk_100mhz) then

            ------------------------------------------------------------
            -- Default
            ------------------------------------------------------------

            sample_tick <= '0';


            if reset = '1' then

                sample_count <= 0;


            else

                if sample_count = SAMPLE_PERIOD_CLKS - 1 then

                    sample_count <= 0;

                    sample_tick <= '1';

                else

                    sample_count <= sample_count + 1;

                end if;

            end if;

        end if;

    end process;



    --------------------------------------------------------------------
    -- ADS8320 DCLOCK GENERATOR
    --
    -- Generates a 2 MHz serial clock only while a conversion
    -- transaction is active.
    --
    -- While state = IDLE:
    --
    --     adc_dclock = 0
    --
    -- This avoids unnecessary switching between conversions.
    --------------------------------------------------------------------

    clock_generator : process(clk_100mhz)

    begin

        if rising_edge(clk_100mhz) then

            ------------------------------------------------------------
            -- Default edge-indicator pulses
            ------------------------------------------------------------

            dclock_rising  <= '0';
            dclock_falling <= '0';


            if reset = '1' then

                clk_div_count <= 0;

                dclock_int <= '0';


            else

                --------------------------------------------------------
                -- IDLE:
                --
                -- ADS8320 is deselected.
                -- Hold DCLOCK LOW and reset the divider.
                --------------------------------------------------------

                if state = IDLE then

                    clk_div_count <= 0;

                    dclock_int <= '0';


                --------------------------------------------------------
                -- Active transaction:
                --
                -- Generate 2 MHz DCLOCK.
                --------------------------------------------------------

                else

                    if clk_div_count = DCLOCK_DIVIDER - 1 then

                        clk_div_count <= 0;


                        ------------------------------------------------
                        -- Toggle DCLOCK
                        ------------------------------------------------

                        if dclock_int = '0' then

                            dclock_int <= '1';

                            dclock_rising <= '1';


                        else

                            dclock_int <= '0';

                            dclock_falling <= '1';

                        end if;


                    else

                        clk_div_count <= clk_div_count + 1;

                    end if;

                end if;

            end if;

        end if;

    end process;



    --------------------------------------------------------------------
    -- DUAL ADS8320 CONTROL / RECEIVE STATE MACHINE
    --------------------------------------------------------------------

    adc_control : process(clk_100mhz)

    begin

        if rising_edge(clk_100mhz) then

            if reset = '1' then

                state <= IDLE;

                cs_n_int <= '1';

                startup_count <= 0;

                bit_count <= 15;

                shift_reg_v <= (others => '0');
                shift_reg_i <= (others => '0');

                voltage_data <= (others => '0');
                current_data <= (others => '0');

                sample_valid <= '0';


            else


                --------------------------------------------------------
                -- sample_valid is normally LOW.
                --
                -- COMPLETE asserts it for one FPGA clock cycle.
                --------------------------------------------------------

                sample_valid <= '0';


                case state is


                    ----------------------------------------------------
                    -- IDLE
                    --
                    -- Wait for the next 10 kS/s sampling instant.
                    --
                    -- CS HIGH
                    -- DCLOCK held LOW by clock_generator
                    ----------------------------------------------------

                    when IDLE =>

                        cs_n_int <= '1';


                        if sample_tick = '1' then

                            ------------------------------------------------
                            -- Begin simultaneous voltage/current
                            -- conversion.
                            ------------------------------------------------

                            cs_n_int <= '0';

                            startup_count <= 0;

                            bit_count <= 15;

                            shift_reg_v <= (others => '0');
                            shift_reg_i <= (others => '0');

                            state <= ACQUIRE;

                        end if;



                    ----------------------------------------------------
                    -- ACQUIRE
                    --
                    -- Ignore the first four falling DCLOCK edges.
                    ----------------------------------------------------

                    when ACQUIRE =>

                        if dclock_falling = '1' then

                            if startup_count = 3 then

                                startup_count <= 0;

                                state <= NULL_BIT;

                            else

                                startup_count <= startup_count + 1;

                            end if;

                        end if;



                    ----------------------------------------------------
                    -- NULL_BIT
                    --
                    -- Falling edge 5:
                    -- ADS8320 places the NULL bit onto DOUT.
                    --
                    -- Do not store it.
                    ----------------------------------------------------

                    when NULL_BIT =>

                        if dclock_falling = '1' then

                            state <= WAIT_B15;

                        end if;



                    ----------------------------------------------------
                    -- WAIT_B15
                    --
                    -- Falling edge 6:
                    -- both ADCs place B15 onto their respective
                    -- DOUT pins.
                    ----------------------------------------------------

                    when WAIT_B15 =>

                        if dclock_falling = '1' then

                            bit_count <= 15;

                            state <= READ_DATA;

                        end if;



                    ----------------------------------------------------
                    -- READ_DATA
                    --
                    -- ADS8320 changes data on falling DCLOCK edges.
                    --
                    -- FPGA therefore samples each data bit on the
                    -- following rising edge.
                    ----------------------------------------------------

                    when READ_DATA =>

                        if dclock_rising = '1' then

                            ------------------------------------------------
                            -- Capture both channels simultaneously
                            ------------------------------------------------

                            shift_reg_v(bit_count) <= adc_dout_v;

                            shift_reg_i(bit_count) <= adc_dout_i;


                            ------------------------------------------------
                            -- B0 received
                            ------------------------------------------------

                            if bit_count = 0 then

                                state <= COMPLETE;

                            else

                                bit_count <= bit_count - 1;

                            end if;

                        end if;



                    ----------------------------------------------------
                    -- COMPLETE
                    --
                    -- Publish both synchronized samples.
                    ----------------------------------------------------

                    when COMPLETE =>

                        voltage_data <= shift_reg_v;

                        current_data <= shift_reg_i;


                        ------------------------------------------------
                        -- One-cycle indication that both values
                        -- are valid.
                        ------------------------------------------------

                        sample_valid <= '1';


                        ------------------------------------------------
                        -- Deselect both ADCs.
                        ------------------------------------------------

                        cs_n_int <= '1';


                        ------------------------------------------------
                        -- Return to IDLE.
                        --
                        -- On the following FPGA clocks,
                        -- clock_generator holds DCLOCK LOW.
                        ------------------------------------------------

                        state <= IDLE;



                    ----------------------------------------------------
                    -- Safety fallback
                    ----------------------------------------------------

                    when others =>

                        state <= IDLE;

                        cs_n_int <= '1';

                        sample_valid <= '0';

                end case;

            end if;

        end if;

    end process;


end architecture rtl;