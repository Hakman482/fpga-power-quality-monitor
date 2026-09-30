library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity dual_rms is

    generic (

        WINDOW_SAMPLES :
            positive := 200

    );

    port (

        clk_100mhz :
            in std_logic;

        reset :
            in std_logic;


        voltage_mV_in :
            in signed(31 downto 0);

        current_uA_in :
            in signed(31 downto 0);


        sample_valid_in :
            in std_logic;


        voltage_rms_mV :
            out unsigned(31 downto 0);

        current_rms_uA :
            out unsigned(31 downto 0);


        rms_valid :
            out std_logic

    );

end entity dual_rms;



architecture rtl of dual_rms is


    ------------------------------------------------------------------
    -- Valid electrical-cycle range
    ------------------------------------------------------------------

    constant MIN_CYCLE_SAMPLES :
        integer := 190;

    constant MAX_CYCLE_SAMPLES :
        integer := 210;



    ------------------------------------------------------------------
    -- Calculation FSM
    ------------------------------------------------------------------

    type state_type is (

        ACQUIRE,

        DIV_V_INIT,
        DIV_V_RUN,

        DIV_I_INIT,
        DIV_I_RUN,

        SQRT_V_INIT,
        SQRT_V_RUN,

        SQRT_I_INIT,
        SQRT_I_RUN,

        OUTPUT_RESULT

    );


    signal state :
        state_type := ACQUIRE;



    ------------------------------------------------------------------
    -- Zero-crossing detector
    ------------------------------------------------------------------

    signal previous_voltage :
        signed(31 downto 0) :=
        (others => '0');



    ------------------------------------------------------------------
    -- PIPELINE STAGE A
    --
    -- Input multiplication results are registered before being
    -- added to the 64-bit accumulators.
    ------------------------------------------------------------------

    signal voltage_square_reg :
        unsigned(63 downto 0) :=
        (others => '0');


    signal current_square_reg :
        unsigned(63 downto 0) :=
        (others => '0');


    signal square_valid_reg :
        std_logic :=
        '0';


    signal crossing_reg :
        std_logic :=
        '0';



    ------------------------------------------------------------------
    -- Electrical-cycle accumulation
    ------------------------------------------------------------------

    signal cycle_started :
        std_logic :=
        '0';


    signal cycle_sample_count :
        integer range 0 to 511 :=
        0;


    signal voltage_sum_sq :
        unsigned(63 downto 0) :=
        (others => '0');


    signal current_sum_sq :
        unsigned(63 downto 0) :=
        (others => '0');



    ------------------------------------------------------------------
    -- Completed-cycle capture
    ------------------------------------------------------------------

    signal captured_voltage_sum :
        unsigned(63 downto 0) :=
        (others => '0');


    signal captured_current_sum :
        unsigned(63 downto 0) :=
        (others => '0');


    signal captured_sample_count :
        unsigned(8 downto 0) :=
        (others => '0');



    ------------------------------------------------------------------
    -- Sequential divider
    ------------------------------------------------------------------

    signal div_dividend :
        unsigned(63 downto 0) :=
        (others => '0');


    signal div_divisor :
        unsigned(8 downto 0) :=
        (others => '0');


    signal div_quotient :
        unsigned(63 downto 0) :=
        (others => '0');


    signal div_remainder :
        unsigned(9 downto 0) :=
        (others => '0');


    signal div_bit_index :
        integer range 0 to 63 :=
        63;



    ------------------------------------------------------------------
    -- Mean-square values
    ------------------------------------------------------------------

    signal voltage_mean_sq :
        unsigned(63 downto 0) :=
        (others => '0');


    signal current_mean_sq :
        unsigned(63 downto 0) :=
        (others => '0');



    ------------------------------------------------------------------
    -- Iterative square-root engine
    ------------------------------------------------------------------

    signal sqrt_radicand :
        unsigned(63 downto 0) :=
        (others => '0');


    signal sqrt_remainder :
        unsigned(65 downto 0) :=
        (others => '0');


    signal sqrt_root :
        unsigned(31 downto 0) :=
        (others => '0');


    signal sqrt_iteration :
        integer range 0 to 31 :=
        0;



    signal voltage_root_result :
        unsigned(31 downto 0) :=
        (others => '0');


    signal current_root_result :
        unsigned(31 downto 0) :=
        (others => '0');



begin


    ------------------------------------------------------------------
    -- MAIN PROCESS
    ------------------------------------------------------------------

    process(clk_100mhz)


        variable voltage_square_s :
            signed(63 downto 0);


        variable current_square_s :
            signed(63 downto 0);



        --------------------------------------------------------------
        -- Divider temporary values
        --------------------------------------------------------------

        variable remainder_shifted :
            unsigned(9 downto 0);


        variable remainder_next :
            unsigned(9 downto 0);


        variable quotient_next :
            unsigned(63 downto 0);



        --------------------------------------------------------------
        -- Square-root temporary values
        --------------------------------------------------------------

        variable sqrt_rem_shifted :
            unsigned(65 downto 0);


        variable sqrt_trial :
            unsigned(65 downto 0);


        variable sqrt_root_shifted :
            unsigned(32 downto 0);


        variable sqrt_root_next :
            unsigned(32 downto 0);


        variable sqrt_rem_next :
            unsigned(65 downto 0);



    begin


        if rising_edge(clk_100mhz) then


            ----------------------------------------------------------
            -- RESET
            ----------------------------------------------------------

            if reset = '1' then


                state <=
                    ACQUIRE;


                previous_voltage <=
                    (others => '0');


                voltage_square_reg <=
                    (others => '0');


                current_square_reg <=
                    (others => '0');


                square_valid_reg <=
                    '0';


                crossing_reg <=
                    '0';


                cycle_started <=
                    '0';


                cycle_sample_count <=
                    0;


                voltage_sum_sq <=
                    (others => '0');


                current_sum_sq <=
                    (others => '0');


                captured_voltage_sum <=
                    (others => '0');


                captured_current_sum <=
                    (others => '0');


                captured_sample_count <=
                    (others => '0');


                div_dividend <=
                    (others => '0');


                div_divisor <=
                    (others => '0');


                div_quotient <=
                    (others => '0');


                div_remainder <=
                    (others => '0');


                div_bit_index <=
                    63;


                voltage_mean_sq <=
                    (others => '0');


                current_mean_sq <=
                    (others => '0');


                sqrt_radicand <=
                    (others => '0');


                sqrt_remainder <=
                    (others => '0');


                sqrt_root <=
                    (others => '0');


                sqrt_iteration <=
                    0;


                voltage_root_result <=
                    (others => '0');


                current_root_result <=
                    (others => '0');


                voltage_rms_mV <=
                    (others => '0');


                current_rms_uA <=
                    (others => '0');


                rms_valid <=
                    '0';



            else


                rms_valid <=
                    '0';


                ------------------------------------------------------
                -- Default pipeline-valid low
                ------------------------------------------------------

                square_valid_reg <=
                    '0';



                ------------------------------------------------------
                -- PIPELINE STAGE A
                --
                -- Square new samples and REGISTER the results.
                --
                -- The accumulator does not see the multiplier output
                -- until the next system clock.
                ------------------------------------------------------

                if sample_valid_in = '1' then


                    voltage_square_s :=
                        voltage_mV_in *
                        voltage_mV_in;


                    current_square_s :=
                        current_uA_in *
                        current_uA_in;


                    voltage_square_reg <=
                        unsigned(
                            voltage_square_s
                        );


                    current_square_reg <=
                        unsigned(
                            current_square_s
                        );


                    --------------------------------------------------
                    -- Detect positive-going zero crossing and
                    -- register it with the corresponding squared
                    -- sample.
                    --------------------------------------------------

                    if
                        previous_voltage < 0
                        and
                        voltage_mV_in >= 0
                    then


                        crossing_reg <=
                            '1';


                    else


                        crossing_reg <=
                            '0';


                    end if;


                    previous_voltage <=
                        voltage_mV_in;


                    square_valid_reg <=
                        '1';


                end if;



                ------------------------------------------------------
                -- PIPELINE STAGE B
                --
                -- Accumulation occurs from REGISTERED square values.
                ------------------------------------------------------

                if square_valid_reg = '1' then


                    --------------------------------------------------
                    -- Positive zero crossing
                    --------------------------------------------------

                    if crossing_reg = '1' then


                        ------------------------------------------------
                        -- Capture completed previous cycle
                        ------------------------------------------------

                        if
                            cycle_started = '1'
                            and
                            cycle_sample_count >=
                                MIN_CYCLE_SAMPLES
                            and
                            cycle_sample_count <=
                                MAX_CYCLE_SAMPLES
                            and
                            state = ACQUIRE
                        then


                            captured_voltage_sum <=
                                voltage_sum_sq;


                            captured_current_sum <=
                                current_sum_sq;


                            captured_sample_count <=
                                to_unsigned(
                                    cycle_sample_count,
                                    captured_sample_count'length
                                );


                            state <=
                                DIV_V_INIT;


                        end if;



                        ------------------------------------------------
                        -- Current crossing sample starts new cycle
                        ------------------------------------------------

                        voltage_sum_sq <=
                            voltage_square_reg;


                        current_sum_sq <=
                            current_square_reg;


                        cycle_sample_count <=
                            1;


                        cycle_started <=
                            '1';



                    --------------------------------------------------
                    -- Continue electrical cycle
                    --------------------------------------------------

                    elsif cycle_started = '1' then


                        voltage_sum_sq <=
                            voltage_sum_sq
                            +
                            voltage_square_reg;


                        current_sum_sq <=
                            current_sum_sq
                            +
                            current_square_reg;


                        if cycle_sample_count < 511 then


                            cycle_sample_count <=
                                cycle_sample_count + 1;


                        end if;


                    end if;


                end if;



                ------------------------------------------------------
                -- CALCULATION FSM
                ------------------------------------------------------

                case state is



                    --------------------------------------------------
                    -- ACQUIRE
                    --------------------------------------------------

                    when ACQUIRE =>

                        null;



                    --------------------------------------------------
                    -- Voltage divider initialization
                    --------------------------------------------------

                    when DIV_V_INIT =>


                        div_dividend <=
                            captured_voltage_sum;


                        div_divisor <=
                            captured_sample_count;


                        div_quotient <=
                            (others => '0');


                        div_remainder <=
                            (others => '0');


                        div_bit_index <=
                            63;


                        state <=
                            DIV_V_RUN;



                    --------------------------------------------------
                    -- Voltage sequential division
                    --------------------------------------------------

                    when DIV_V_RUN =>


                        remainder_shifted :=
                            shift_left(
                                div_remainder,
                                1
                            );


                        remainder_shifted(0) :=
                            div_dividend(
                                div_bit_index
                            );


                        quotient_next :=
                            div_quotient;


                        remainder_next :=
                            remainder_shifted;



                        if
                            remainder_shifted >=
                            resize(
                                div_divisor,
                                remainder_shifted'length
                            )
                        then


                            remainder_next :=
                                remainder_shifted
                                -
                                resize(
                                    div_divisor,
                                    remainder_shifted'length
                                );


                            quotient_next(
                                div_bit_index
                            ) :=
                                '1';


                        else


                            quotient_next(
                                div_bit_index
                            ) :=
                                '0';


                        end if;


                        div_remainder <=
                            remainder_next;


                        div_quotient <=
                            quotient_next;



                        if div_bit_index = 0 then


                            voltage_mean_sq <=
                                quotient_next;


                            state <=
                                DIV_I_INIT;


                        else


                            div_bit_index <=
                                div_bit_index - 1;


                        end if;



                    --------------------------------------------------
                    -- Current divider initialization
                    --------------------------------------------------

                    when DIV_I_INIT =>


                        div_dividend <=
                            captured_current_sum;


                        div_divisor <=
                            captured_sample_count;


                        div_quotient <=
                            (others => '0');


                        div_remainder <=
                            (others => '0');


                        div_bit_index <=
                            63;


                        state <=
                            DIV_I_RUN;



                    --------------------------------------------------
                    -- Current sequential division
                    --------------------------------------------------

                    when DIV_I_RUN =>


                        remainder_shifted :=
                            shift_left(
                                div_remainder,
                                1
                            );


                        remainder_shifted(0) :=
                            div_dividend(
                                div_bit_index
                            );


                        quotient_next :=
                            div_quotient;


                        remainder_next :=
                            remainder_shifted;



                        if
                            remainder_shifted >=
                            resize(
                                div_divisor,
                                remainder_shifted'length
                            )
                        then


                            remainder_next :=
                                remainder_shifted
                                -
                                resize(
                                    div_divisor,
                                    remainder_shifted'length
                                );


                            quotient_next(
                                div_bit_index
                            ) :=
                                '1';


                        else


                            quotient_next(
                                div_bit_index
                            ) :=
                                '0';


                        end if;


                        div_remainder <=
                            remainder_next;


                        div_quotient <=
                            quotient_next;



                        if div_bit_index = 0 then


                            current_mean_sq <=
                                quotient_next;


                            state <=
                                SQRT_V_INIT;


                        else


                            div_bit_index <=
                                div_bit_index - 1;


                        end if;



                    --------------------------------------------------
                    -- Voltage square-root initialization
                    --------------------------------------------------

                    when SQRT_V_INIT =>


                        sqrt_radicand <=
                            voltage_mean_sq;


                        sqrt_remainder <=
                            (others => '0');


                        sqrt_root <=
                            (others => '0');


                        sqrt_iteration <=
                            0;


                        state <=
                            SQRT_V_RUN;



                    --------------------------------------------------
                    -- Iterative voltage square root
                    --------------------------------------------------

                    when SQRT_V_RUN =>


                        sqrt_root_shifted :=
                            shift_left(
                                resize(
                                    sqrt_root,
                                    33
                                ),
                                1
                            );


                        sqrt_rem_shifted :=
                            shift_left(
                                sqrt_remainder,
                                2
                            );


                        sqrt_rem_shifted(1 downto 0) :=
                            sqrt_radicand(
                                63 downto 62
                            );


                        sqrt_radicand <=
                            shift_left(
                                sqrt_radicand,
                                2
                            );


                        sqrt_trial :=
                            shift_left(
                                resize(
                                    sqrt_root_shifted,
                                    66
                                ),
                                1
                            );


                        sqrt_trial(0) :=
                            '1';


                        sqrt_root_next :=
                            sqrt_root_shifted;


                        sqrt_rem_next :=
                            sqrt_rem_shifted;



                        if sqrt_rem_shifted >= sqrt_trial then


                            sqrt_rem_next :=
                                sqrt_rem_shifted
                                -
                                sqrt_trial;


                            sqrt_root_next(0) :=
                                '1';


                        end if;


                        sqrt_remainder <=
                            sqrt_rem_next;


                        sqrt_root <=
                            sqrt_root_next(
                                31 downto 0
                            );



                        if sqrt_iteration = 31 then


                            voltage_root_result <=
                                sqrt_root_next(
                                    31 downto 0
                                );


                            state <=
                                SQRT_I_INIT;


                        else


                            sqrt_iteration <=
                                sqrt_iteration + 1;


                        end if;



                    --------------------------------------------------
                    -- Current square-root initialization
                    --------------------------------------------------

                    when SQRT_I_INIT =>


                        sqrt_radicand <=
                            current_mean_sq;


                        sqrt_remainder <=
                            (others => '0');


                        sqrt_root <=
                            (others => '0');


                        sqrt_iteration <=
                            0;


                        state <=
                            SQRT_I_RUN;



                    --------------------------------------------------
                    -- Iterative current square root
                    --------------------------------------------------

                    when SQRT_I_RUN =>


                        sqrt_root_shifted :=
                            shift_left(
                                resize(
                                    sqrt_root,
                                    33
                                ),
                                1
                            );


                        sqrt_rem_shifted :=
                            shift_left(
                                sqrt_remainder,
                                2
                            );


                        sqrt_rem_shifted(1 downto 0) :=
                            sqrt_radicand(
                                63 downto 62
                            );


                        sqrt_radicand <=
                            shift_left(
                                sqrt_radicand,
                                2
                            );


                        sqrt_trial :=
                            shift_left(
                                resize(
                                    sqrt_root_shifted,
                                    66
                                ),
                                1
                            );


                        sqrt_trial(0) :=
                            '1';


                        sqrt_root_next :=
                            sqrt_root_shifted;


                        sqrt_rem_next :=
                            sqrt_rem_shifted;



                        if sqrt_rem_shifted >= sqrt_trial then


                            sqrt_rem_next :=
                                sqrt_rem_shifted
                                -
                                sqrt_trial;


                            sqrt_root_next(0) :=
                                '1';


                        end if;


                        sqrt_remainder <=
                            sqrt_rem_next;


                        sqrt_root <=
                            sqrt_root_next(
                                31 downto 0
                            );



                        if sqrt_iteration = 31 then


                            current_root_result <=
                                sqrt_root_next(
                                    31 downto 0
                                );


                            state <=
                                OUTPUT_RESULT;


                        else


                            sqrt_iteration <=
                                sqrt_iteration + 1;


                        end if;



                    --------------------------------------------------
                    -- Publish RMS result
                    --------------------------------------------------

                    when OUTPUT_RESULT =>


                        voltage_rms_mV <=
                            voltage_root_result;


                        current_rms_uA <=
                            current_root_result;


                        rms_valid <=
                            '1';


                        state <=
                            ACQUIRE;



                    when others =>


                        state <=
                            ACQUIRE;


                end case;


            end if;


        end if;


    end process;


end architecture rtl;