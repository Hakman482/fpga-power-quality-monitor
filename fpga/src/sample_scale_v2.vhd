library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity sample_scale_v2 is

    port (

        --------------------------------------------------------------
        -- FPGA system signals
        --------------------------------------------------------------
        clk_100mhz : in std_logic;
        reset      : in std_logic;


        --------------------------------------------------------------
        -- Zero-centred ADC-count inputs
        --------------------------------------------------------------
        voltage_signed_in : in signed(16 downto 0);
        current_signed_in : in signed(16 downto 0);

        sample_valid_in : in std_logic;


        --------------------------------------------------------------
        -- Physical quantities
        --------------------------------------------------------------
        voltage_mV : out signed(31 downto 0);
        current_uA : out signed(31 downto 0);


        --------------------------------------------------------------
        -- One-clock output-valid pulse
        --------------------------------------------------------------
        sample_valid_out : out std_logic

    );

end entity sample_scale_v2;



architecture rtl of sample_scale_v2 is


    ------------------------------------------------------------------
    -- Scaling constants
    --
    -- Voltage:
    --
    --     count * 14422 / 1000
    --
    -- This is the preliminary measured calibration:
    --
    --     14.422 mV per ADC count
    --
    -- Current:
    --
    --     count * 47684 / 1000
    ------------------------------------------------------------------

    constant VOLTAGE_SCALE_NUM :
        unsigned(15 downto 0) :=
        to_unsigned(14422, 16);


    constant CURRENT_SCALE_NUM :
        unsigned(15 downto 0) :=
        to_unsigned(47684, 16);


    constant SCALE_DEN :
        unsigned(47 downto 0) :=
        to_unsigned(1000, 48);



    ------------------------------------------------------------------
    -- State machine
    ------------------------------------------------------------------

    type state_type is (

        IDLE,

        MULTIPLY,

        DIV_SETUP,

        DIVIDE,

        OUTPUT_RESULT

    );


    signal state :
        state_type := IDLE;



    ------------------------------------------------------------------
    -- Original sample signs
    ------------------------------------------------------------------

    signal voltage_negative :
        std_logic := '0';

    signal current_negative :
        std_logic := '0';



    ------------------------------------------------------------------
    -- Sequential constant multiplier
    --
    -- Both voltage and current calculations operate in parallel.
    ------------------------------------------------------------------

    signal voltage_mult_multiplicand :
        unsigned(47 downto 0) :=
        (others => '0');

    signal current_mult_multiplicand :
        unsigned(47 downto 0) :=
        (others => '0');


    signal voltage_mult_multiplier :
        unsigned(15 downto 0) :=
        (others => '0');

    signal current_mult_multiplier :
        unsigned(15 downto 0) :=
        (others => '0');


    signal voltage_mult_accumulator :
        unsigned(47 downto 0) :=
        (others => '0');

    signal current_mult_accumulator :
        unsigned(47 downto 0) :=
        (others => '0');


    signal mult_bit_index :
        integer range 0 to 15 := 0;



    ------------------------------------------------------------------
    -- Parallel sequential dividers
    --
    -- Divide both products by 1000.
    ------------------------------------------------------------------

    signal voltage_dividend :
        unsigned(47 downto 0) :=
        (others => '0');

    signal current_dividend :
        unsigned(47 downto 0) :=
        (others => '0');


    signal voltage_quotient :
        unsigned(47 downto 0) :=
        (others => '0');

    signal current_quotient :
        unsigned(47 downto 0) :=
        (others => '0');


    signal voltage_remainder :
        unsigned(48 downto 0) :=
        (others => '0');

    signal current_remainder :
        unsigned(48 downto 0) :=
        (others => '0');


    signal div_bit_index :
        integer range 0 to 47 := 47;



    ------------------------------------------------------------------
    -- Final unsigned magnitudes
    ------------------------------------------------------------------

    signal voltage_scaled_mag :
        unsigned(47 downto 0) :=
        (others => '0');

    signal current_scaled_mag :
        unsigned(47 downto 0) :=
        (others => '0');


begin


    ------------------------------------------------------------------
    -- Scaling processor
    ------------------------------------------------------------------

    scale_process : process(clk_100mhz)


        --------------------------------------------------------------
        -- Input magnitude calculation
        --------------------------------------------------------------

        variable voltage_temp :
            signed(17 downto 0);

        variable current_temp :
            signed(17 downto 0);


        variable voltage_mag_temp :
            unsigned(17 downto 0);

        variable current_mag_temp :
            unsigned(17 downto 0);



        --------------------------------------------------------------
        -- Multiplier next values
        --------------------------------------------------------------

        variable voltage_mult_next :
            unsigned(47 downto 0);

        variable current_mult_next :
            unsigned(47 downto 0);



        --------------------------------------------------------------
        -- Divider working values
        --------------------------------------------------------------

        variable voltage_rem_shift :
            unsigned(48 downto 0);

        variable current_rem_shift :
            unsigned(48 downto 0);


        variable divisor_extended :
            unsigned(48 downto 0);


        variable voltage_quot_next :
            unsigned(47 downto 0);

        variable current_quot_next :
            unsigned(47 downto 0);



        --------------------------------------------------------------
        -- Final signed values
        --------------------------------------------------------------

        variable voltage_result_48 :
            signed(47 downto 0);

        variable current_result_48 :
            signed(47 downto 0);


    begin


        if rising_edge(clk_100mhz) then


            ----------------------------------------------------------
            -- RESET
            ----------------------------------------------------------

            if reset = '1' then


                state <=
                    IDLE;


                voltage_negative <=
                    '0';

                current_negative <=
                    '0';


                voltage_mult_multiplicand <=
                    (others => '0');

                current_mult_multiplicand <=
                    (others => '0');


                voltage_mult_multiplier <=
                    (others => '0');

                current_mult_multiplier <=
                    (others => '0');


                voltage_mult_accumulator <=
                    (others => '0');

                current_mult_accumulator <=
                    (others => '0');


                mult_bit_index <=
                    0;


                voltage_dividend <=
                    (others => '0');

                current_dividend <=
                    (others => '0');


                voltage_quotient <=
                    (others => '0');

                current_quotient <=
                    (others => '0');


                voltage_remainder <=
                    (others => '0');

                current_remainder <=
                    (others => '0');


                div_bit_index <=
                    47;


                voltage_scaled_mag <=
                    (others => '0');

                current_scaled_mag <=
                    (others => '0');


                voltage_mV <=
                    (others => '0');

                current_uA <=
                    (others => '0');


                sample_valid_out <=
                    '0';



            else


                ------------------------------------------------------
                -- Valid is a one-clock pulse
                ------------------------------------------------------

                sample_valid_out <=
                    '0';



                case state is


                    --------------------------------------------------
                    -- Wait for synchronized ADC sample pair
                    --------------------------------------------------

                    when IDLE =>


                        if sample_valid_in = '1' then


                            ------------------------------------------------
                            -- Voltage sign and magnitude
                            ------------------------------------------------

                            voltage_temp :=
                                resize(
                                    voltage_signed_in,
                                    18
                                );


                            if voltage_temp < 0 then


                                voltage_negative <=
                                    '1';


                                voltage_mag_temp :=
                                    unsigned(
                                        -voltage_temp
                                    );


                            else


                                voltage_negative <=
                                    '0';


                                voltage_mag_temp :=
                                    unsigned(
                                        voltage_temp
                                    );


                            end if;



                            ------------------------------------------------
                            -- Current sign and magnitude
                            ------------------------------------------------

                            current_temp :=
                                resize(
                                    current_signed_in,
                                    18
                                );


                            if current_temp < 0 then


                                current_negative <=
                                    '1';


                                current_mag_temp :=
                                    unsigned(
                                        -current_temp
                                    );


                            else


                                current_negative <=
                                    '0';


                                current_mag_temp :=
                                    unsigned(
                                        current_temp
                                    );


                            end if;



                            ------------------------------------------------
                            -- Initialise voltage constant multiplier
                            ------------------------------------------------

                            voltage_mult_multiplicand <=
                                resize(
                                    voltage_mag_temp,
                                    48
                                );


                            voltage_mult_multiplier <=
                                VOLTAGE_SCALE_NUM;


                            voltage_mult_accumulator <=
                                (others => '0');



                            ------------------------------------------------
                            -- Initialise current constant multiplier
                            ------------------------------------------------

                            current_mult_multiplicand <=
                                resize(
                                    current_mag_temp,
                                    48
                                );


                            current_mult_multiplier <=
                                CURRENT_SCALE_NUM;


                            current_mult_accumulator <=
                                (others => '0');


                            mult_bit_index <=
                                0;


                            state <=
                                MULTIPLY;


                        end if;



                    --------------------------------------------------
                    -- Sequential multiplication
                    --
                    -- One constant-multiplier bit per clock.
                    --
                    -- Voltage and current execute in parallel.
                    --------------------------------------------------

                    when MULTIPLY =>


                        voltage_mult_next :=
                            voltage_mult_accumulator;


                        current_mult_next :=
                            current_mult_accumulator;



                        ------------------------------------------------
                        -- Voltage multiply
                        ------------------------------------------------

                        if voltage_mult_multiplier(0) = '1' then


                            voltage_mult_next :=
                                voltage_mult_accumulator +
                                voltage_mult_multiplicand;


                        end if;



                        ------------------------------------------------
                        -- Current multiply
                        ------------------------------------------------

                        if current_mult_multiplier(0) = '1' then


                            current_mult_next :=
                                current_mult_accumulator +
                                current_mult_multiplicand;


                        end if;



                        ------------------------------------------------
                        -- Store multiplier accumulators
                        ------------------------------------------------

                        voltage_mult_accumulator <=
                            voltage_mult_next;


                        current_mult_accumulator <=
                            current_mult_next;



                        ------------------------------------------------
                        -- Shift multiplier operands
                        ------------------------------------------------

                        voltage_mult_multiplicand <=
                            shift_left(
                                voltage_mult_multiplicand,
                                1
                            );


                        current_mult_multiplicand <=
                            shift_left(
                                current_mult_multiplicand,
                                1
                            );


                        voltage_mult_multiplier <=
                            shift_right(
                                voltage_mult_multiplier,
                                1
                            );


                        current_mult_multiplier <=
                            shift_right(
                                current_mult_multiplier,
                                1
                            );



                        ------------------------------------------------
                        -- 16 multiplier bits complete
                        ------------------------------------------------

                        if mult_bit_index = 15 then


                            voltage_dividend <=
                                voltage_mult_next;


                            current_dividend <=
                                current_mult_next;


                            mult_bit_index <=
                                0;


                            state <=
                                DIV_SETUP;


                        else


                            mult_bit_index <=
                                mult_bit_index + 1;


                        end if;



                    --------------------------------------------------
                    -- Initialise both /1000 dividers
                    --------------------------------------------------

                    when DIV_SETUP =>


                        voltage_quotient <=
                            (others => '0');


                        current_quotient <=
                            (others => '0');


                        voltage_remainder <=
                            (others => '0');


                        current_remainder <=
                            (others => '0');


                        div_bit_index <=
                            47;


                        state <=
                            DIVIDE;



                    --------------------------------------------------
                    -- Parallel restoring division
                    --
                    -- One quotient bit per clock.
                    --------------------------------------------------

                    when DIVIDE =>


                        divisor_extended :=
                            resize(
                                SCALE_DEN,
                                49
                            );



                        ------------------------------------------------
                        -- Voltage divider
                        ------------------------------------------------

                        voltage_rem_shift :=
                            shift_left(
                                voltage_remainder,
                                1
                            );


                        voltage_rem_shift(0) :=
                            voltage_dividend(
                                div_bit_index
                            );


                        voltage_quot_next :=
                            voltage_quotient;


                        if voltage_rem_shift >=
                           divisor_extended
                        then


                            voltage_remainder <=
                                voltage_rem_shift -
                                divisor_extended;


                            voltage_quot_next(
                                div_bit_index
                            ) := '1';


                        else


                            voltage_remainder <=
                                voltage_rem_shift;


                            voltage_quot_next(
                                div_bit_index
                            ) := '0';


                        end if;


                        voltage_quotient <=
                            voltage_quot_next;



                        ------------------------------------------------
                        -- Current divider
                        ------------------------------------------------

                        current_rem_shift :=
                            shift_left(
                                current_remainder,
                                1
                            );


                        current_rem_shift(0) :=
                            current_dividend(
                                div_bit_index
                            );


                        current_quot_next :=
                            current_quotient;


                        if current_rem_shift >=
                           divisor_extended
                        then


                            current_remainder <=
                                current_rem_shift -
                                divisor_extended;


                            current_quot_next(
                                div_bit_index
                            ) := '1';


                        else


                            current_remainder <=
                                current_rem_shift;


                            current_quot_next(
                                div_bit_index
                            ) := '0';


                        end if;


                        current_quotient <=
                            current_quot_next;



                        ------------------------------------------------
                        -- Final quotient bit
                        ------------------------------------------------

                        if div_bit_index = 0 then


                            voltage_scaled_mag <=
                                voltage_quot_next;


                            current_scaled_mag <=
                                current_quot_next;


                            div_bit_index <=
                                47;


                            state <=
                                OUTPUT_RESULT;


                        else


                            div_bit_index <=
                                div_bit_index - 1;


                        end if;



                    --------------------------------------------------
                    -- Restore signs and publish sample
                    --------------------------------------------------

                    when OUTPUT_RESULT =>


                        ------------------------------------------------
                        -- Voltage
                        ------------------------------------------------

                        if voltage_negative = '1' then


                            voltage_result_48 :=
                                -signed(
                                    voltage_scaled_mag
                                );


                        else


                            voltage_result_48 :=
                                signed(
                                    voltage_scaled_mag
                                );


                        end if;



                        ------------------------------------------------
                        -- Current
                        ------------------------------------------------

                        if current_negative = '1' then


                            current_result_48 :=
                                -signed(
                                    current_scaled_mag
                                );


                        else


                            current_result_48 :=
                                signed(
                                    current_scaled_mag
                                );


                        end if;



                        ------------------------------------------------
                        -- Publish physical quantities
                        ------------------------------------------------

                        voltage_mV <=
                            resize(
                                voltage_result_48,
                                voltage_mV'length
                            );


                        current_uA <=
                            resize(
                                current_result_48,
                                current_uA'length
                            );


                        sample_valid_out <=
                            '1';


                        state <=
                            IDLE;


                end case;

            end if;

        end if;

    end process;


end architecture rtl;