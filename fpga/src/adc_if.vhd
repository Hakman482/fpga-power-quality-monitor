library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity dual_adc_if is

    generic (

        --------------------------------------------------------------
        -- FPGA clock
        --------------------------------------------------------------
        SYS_CLK_HZ :
            positive := 100_000_000;

        --------------------------------------------------------------
        -- ADS8320 serial clock
        --------------------------------------------------------------
        ADC_DCLOCK_HZ :
            positive := 2_000_000;

        --------------------------------------------------------------
        -- Required conversion/sample rate
        --------------------------------------------------------------
        SAMPLE_RATE_HZ :
            positive := 10_000

    );

    port (

        --------------------------------------------------------------
        -- FPGA
        --------------------------------------------------------------
        clk_100mhz :
            in std_logic;

        reset :
            in std_logic;


        --------------------------------------------------------------
        -- ADS8320 serial outputs
        --
        -- Voltage ADC
        -- Current ADC
        --------------------------------------------------------------
        adc_dout_v :
            in std_logic;

        adc_dout_i :
            in std_logic;


        --------------------------------------------------------------
        -- Shared ADS8320 control
        --------------------------------------------------------------
        adc_cs_n :
            out std_logic;

        adc_dclock :
            out std_logic;


        --------------------------------------------------------------
        -- Simultaneously captured conversion results
        --------------------------------------------------------------
        voltage_data :
            out std_logic_vector(15 downto 0);

        current_data :
            out std_logic_vector(15 downto 0);


        --------------------------------------------------------------
        -- One-clock pulse when both results are available
        --------------------------------------------------------------
        sample_valid :
            out std_logic

    );

end entity dual_adc_if;



architecture rtl of dual_adc_if is


    ------------------------------------------------------------------
    -- Clock divider
    --
    -- 100 MHz / (2 × 25) = 2 MHz
    ------------------------------------------------------------------

    constant HALF_DCLOCK_COUNT :
        positive :=
        SYS_CLK_HZ / (2 * ADC_DCLOCK_HZ);


    ------------------------------------------------------------------
    -- Sample period
    --
    -- 100 MHz / 10 kHz = 10,000 FPGA clocks
    ------------------------------------------------------------------

    constant SAMPLE_PERIOD_CLKS :
        positive :=
        SYS_CLK_HZ / SAMPLE_RATE_HZ;



    ------------------------------------------------------------------
    -- Sampling interval counter
    ------------------------------------------------------------------

    signal sample_timer :
        integer range 0 to SAMPLE_PERIOD_CLKS - 1 :=
        0;



    ------------------------------------------------------------------
    -- DCLOCK divider counter
    ------------------------------------------------------------------

    signal dclock_counter :
        integer range 0 to HALF_DCLOCK_COUNT - 1 :=
        0;


    signal dclock_int :
        std_logic :=
        '0';



    ------------------------------------------------------------------
    -- Internal pulses corresponding to generated ADC clock edges
    ------------------------------------------------------------------

    signal dclock_rising :
        std_logic :=
        '0';


    signal dclock_falling :
        std_logic :=
        '0';



    ------------------------------------------------------------------
    -- Chip select
    ------------------------------------------------------------------

    signal cs_n_int :
        std_logic :=
        '1';



    ------------------------------------------------------------------
    -- ADC receive registers
    ------------------------------------------------------------------

    signal voltage_shift_reg :
        std_logic_vector(15 downto 0) :=
        (others => '0');


    signal current_shift_reg :
        std_logic_vector(15 downto 0) :=
        (others => '0');



    ------------------------------------------------------------------
    -- Count falling DCLOCK edges after CS goes LOW.
    --
    -- ADS8320:
    --
    -- falling edge 1 ... 5 = acquisition/conversion startup
    -- following period     = NULL bit
    -- next 16 periods      = B15 ... B0
    ------------------------------------------------------------------

    signal falling_edge_count :
        integer range 0 to 21 :=
        0;



    ------------------------------------------------------------------
    -- Data bit counter
    ------------------------------------------------------------------

    signal bit_count :
        integer range 0 to 15 :=
        15;



    ------------------------------------------------------------------
    -- State machine
    ------------------------------------------------------------------

    type state_type is (

        WAIT_SAMPLE,
        START_CONVERSION,
        ACQUIRE_CONVERT,
        READ_BITS,
        FINISH_CONVERSION

    );


    signal state :
        state_type :=
        WAIT_SAMPLE;



begin


    ------------------------------------------------------------------
    -- Outputs
    ------------------------------------------------------------------

    adc_cs_n <=
        cs_n_int;


    adc_dclock <=
        dclock_int;



    ------------------------------------------------------------------
    -- ADC serial clock generator
    --
    -- DCLOCK only runs while CS is LOW.
    ------------------------------------------------------------------

    clock_generator :
    process(clk_100mhz)

    begin

        if rising_edge(clk_100mhz) then


            ----------------------------------------------------------
            -- Default edge indicators LOW
            ----------------------------------------------------------

            dclock_rising <=
                '0';


            dclock_falling <=
                '0';



            if reset = '1' then


                dclock_counter <=
                    0;


                dclock_int <=
                    '0';


            else


                ------------------------------------------------------
                -- Keep DCLOCK LOW while ADCs are idle
                ------------------------------------------------------

                if cs_n_int = '1' then


                    dclock_counter <=
                        0;


                    dclock_int <=
                        '0';



                else


                    --------------------------------------------------
                    -- Generate ADC clock
                    --------------------------------------------------

                    if dclock_counter =
                       HALF_DCLOCK_COUNT - 1
                    then


                        dclock_counter <=
                            0;



                        if dclock_int = '0' then


                            dclock_int <=
                                '1';


                            dclock_rising <=
                                '1';


                        else


                            dclock_int <=
                                '0';


                            dclock_falling <=
                                '1';


                        end if;


                    else


                        dclock_counter <=
                            dclock_counter + 1;


                    end if;


                end if;


            end if;


        end if;


    end process;



    ------------------------------------------------------------------
    -- ADS8320 dual conversion controller
    ------------------------------------------------------------------

    adc_controller :
    process(clk_100mhz)

    begin


        if rising_edge(clk_100mhz) then


            if reset = '1' then


                state <=
                    WAIT_SAMPLE;


                sample_timer <=
                    0;


                cs_n_int <=
                    '1';


                falling_edge_count <=
                    0;


                bit_count <=
                    15;


                voltage_shift_reg <=
                    (others => '0');


                current_shift_reg <=
                    (others => '0');


                voltage_data <=
                    (others => '0');


                current_data <=
                    (others => '0');


                sample_valid <=
                    '0';



            else


                ------------------------------------------------------
                -- sample_valid is only a one-clock pulse
                ------------------------------------------------------

                sample_valid <=
                    '0';



                case state is


                    --------------------------------------------------
                    -- Wait until next 10 kS/s sample instant
                    --------------------------------------------------

                    when WAIT_SAMPLE =>


                        cs_n_int <=
                            '1';



                        if sample_timer =
                           SAMPLE_PERIOD_CLKS - 1
                        then


                            sample_timer <=
                                0;


                            state <=
                                START_CONVERSION;


                        else


                            sample_timer <=
                                sample_timer + 1;


                        end if;



                    --------------------------------------------------
                    -- Falling CS starts both ADS8320 conversions
                    --------------------------------------------------

                    when START_CONVERSION =>


                        cs_n_int <=
                            '0';


                        falling_edge_count <=
                            0;


                        bit_count <=
                            15;


                        voltage_shift_reg <=
                            (others => '0');


                        current_shift_reg <=
                            (others => '0');


                        state <=
                            ACQUIRE_CONVERT;



                    --------------------------------------------------
                    -- ADS8320 acquisition / NULL phase
                    --------------------------------------------------

                    when ACQUIRE_CONVERT =>


                        if dclock_falling = '1' then


                            ------------------------------------------------
                            -- Count first six falling edges:
                            --
                            -- 1-5 : acquisition/conversion startup
                            -- 6   : NULL bit transition
                            --
                            -- B15 is then stable for capture on the
                            -- following rising DCLOCK edge.
                            ------------------------------------------------

                            if falling_edge_count = 5 then


                                bit_count <=
                                    15;


                                state <=
                                    READ_BITS;


                            else


                                falling_edge_count <=
                                    falling_edge_count + 1;


                            end if;


                        end if;



                    --------------------------------------------------
                    -- Capture B15 ... B0 simultaneously
                    --
                    -- ADS8320 updates DOUT on falling DCLOCK.
                    -- We sample on rising DCLOCK.
                    --------------------------------------------------

                    when READ_BITS =>


                        if dclock_rising = '1' then


                            voltage_shift_reg(bit_count) <=
                                adc_dout_v;


                            current_shift_reg(bit_count) <=
                                adc_dout_i;



                            if bit_count = 0 then


                                state <=
                                    FINISH_CONVERSION;


                            else


                                bit_count <=
                                    bit_count - 1;


                            end if;


                        end if;



                    --------------------------------------------------
                    -- Publish both 16-bit words together
                    --------------------------------------------------

                    when FINISH_CONVERSION =>


                        voltage_data <=
                            voltage_shift_reg;


                        current_data <=
                            current_shift_reg;


                        ------------------------------------------------
                        -- Raising CS completes the transaction and
                        -- returns both ADCs to power-down mode.
                        ------------------------------------------------

                        cs_n_int <=
                            '1';


                        sample_valid <=
                            '1';


                        state <=
                            WAIT_SAMPLE;



                end case;


            end if;


        end if;


    end process;


end architecture rtl;