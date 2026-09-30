library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity power_meter_v2 is

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


        voltage_rms_mV_in :
            in unsigned(31 downto 0);

        current_rms_uA_in :
            in unsigned(31 downto 0);

        rms_valid_in :
            in std_logic;


        active_power_mW :
            out signed(31 downto 0);

        apparent_power_mVA :
            out unsigned(31 downto 0);

        power_factor_milli :
            out signed(15 downto 0);


        power_valid :
            out std_logic

    );

end entity power_meter_v2;



architecture rtl of power_meter_v2 is


    ------------------------------------------------------------------
    -- Valid cycle range
    ------------------------------------------------------------------

    constant MIN_CYCLE_SAMPLES :
        integer := 190;

    constant MAX_CYCLE_SAMPLES :
        integer := 210;



    ------------------------------------------------------------------
    -- Input multiplier pipeline
    ------------------------------------------------------------------

    signal instant_power_reg :
        signed(63 downto 0) :=
        (others => '0');


    signal instant_power_valid_reg :
        std_logic :=
        '0';


    signal crossing_reg :
        std_logic :=
        '0';


    signal previous_voltage :
        signed(31 downto 0) :=
        (others => '0');



    ------------------------------------------------------------------
    -- Cycle-synchronous active-power accumulation
    ------------------------------------------------------------------

    signal cycle_started :
        std_logic :=
        '0';


    signal cycle_sample_count :
        integer range 0 to 511 :=
        0;


    signal power_sum_nW :
        signed(63 downto 0) :=
        (others => '0');



    ------------------------------------------------------------------
    -- Captured cycle
    ------------------------------------------------------------------

    signal captured_power_sum_nW :
        signed(63 downto 0) :=
        (others => '0');


    signal captured_sample_count :
        unsigned(8 downto 0) :=
        (others => '0');


    signal power_cycle_ready :
        std_logic :=
        '0';



    ------------------------------------------------------------------
    -- Latched RMS pair
    ------------------------------------------------------------------

    signal rms_voltage_latched :
        unsigned(31 downto 0) :=
        (others => '0');


    signal rms_current_latched :
        unsigned(31 downto 0) :=
        (others => '0');


    signal rms_ready :
        std_logic :=
        '0';



    ------------------------------------------------------------------
    -- Calculation FSM
    ------------------------------------------------------------------

    type state_type is (

        IDLE,

        ACTIVE_DIV_INIT,
        ACTIVE_DIV_RUN,

        ACTIVE_SCALE_INIT,
        ACTIVE_SCALE_RUN,

        APPARENT_MUL,
        APPARENT_DIV_INIT,
        APPARENT_DIV_RUN,

        PF_NUMERATOR,
        PF_DIV_INIT,
        PF_DIV_RUN,

        --------------------------------------------------------------
        -- Extra PF pipeline stages
        --------------------------------------------------------------
        PF_ANALYZE,
        PF_CLAMP,
        PF_SIGN,

        OUTPUT_RESULT

    );


    signal state :
        state_type :=
        IDLE;



    ------------------------------------------------------------------
    -- Shared 64-bit iterative divider
    ------------------------------------------------------------------

    signal div_dividend :
        unsigned(63 downto 0) :=
        (others => '0');


    signal div_divisor :
        unsigned(63 downto 0) :=
        (others => '0');


    signal div_quotient :
        unsigned(63 downto 0) :=
        (others => '0');


    signal div_remainder :
        unsigned(64 downto 0) :=
        (others => '0');


    signal div_bit_index :
        integer range 0 to 63 :=
        63;



    ------------------------------------------------------------------
    -- Active-power results
    ------------------------------------------------------------------

    signal active_negative :
        std_logic :=
        '0';


    signal active_mean_nW :
        unsigned(63 downto 0) :=
        (others => '0');


    signal active_abs_mW :
        unsigned(63 downto 0) :=
        (others => '0');


    signal active_result_mW :
        signed(63 downto 0) :=
        (others => '0');



    ------------------------------------------------------------------
    -- Apparent-power pipeline
    ------------------------------------------------------------------

    signal apparent_nVA_reg :
        unsigned(63 downto 0) :=
        (others => '0');


    signal apparent_result_mVA :
        unsigned(63 downto 0) :=
        (others => '0');



    ------------------------------------------------------------------
    -- Power-factor pipeline
    ------------------------------------------------------------------

    signal pf_numerator_reg :
        unsigned(63 downto 0) :=
        (others => '0');


    signal pf_raw_reg :
        unsigned(63 downto 0) :=
        (others => '0');



    ------------------------------------------------------------------
    -- NEW TIMING PIPELINE
    --
    -- PF_ANALYZE performs the wide comparison once and registers
    -- only:
    --
    --   1. whether PF exceeds 1.000
    --   2. the low 16 quotient bits
    --
    -- PF_CLAMP therefore contains only a very small 16-bit mux.
    ------------------------------------------------------------------

    signal pf_over_unity_reg :
        std_logic :=
        '0';


    signal pf_low16_reg :
        unsigned(15 downto 0) :=
        (others => '0');


    signal pf_clamped_reg :
        unsigned(15 downto 0) :=
        (others => '0');


    signal pf_result_milli :
        signed(15 downto 0) :=
        (others => '0');



begin


    power_process :
    process(clk_100mhz)


        variable instant_power_v :
            signed(63 downto 0);


        variable remainder_shifted :
            unsigned(64 downto 0);


        variable remainder_next :
            unsigned(64 downto 0);


        variable quotient_next :
            unsigned(63 downto 0);


    begin


        if rising_edge(clk_100mhz) then


            ----------------------------------------------------------
            -- RESET
            ----------------------------------------------------------

            if reset = '1' then


                instant_power_reg <=
                    (others => '0');


                instant_power_valid_reg <=
                    '0';


                crossing_reg <=
                    '0';


                previous_voltage <=
                    (others => '0');


                cycle_started <=
                    '0';


                cycle_sample_count <=
                    0;


                power_sum_nW <=
                    (others => '0');


                captured_power_sum_nW <=
                    (others => '0');


                captured_sample_count <=
                    (others => '0');


                power_cycle_ready <=
                    '0';


                rms_voltage_latched <=
                    (others => '0');


                rms_current_latched <=
                    (others => '0');


                rms_ready <=
                    '0';


                state <=
                    IDLE;


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


                active_negative <=
                    '0';


                active_mean_nW <=
                    (others => '0');


                active_abs_mW <=
                    (others => '0');


                active_result_mW <=
                    (others => '0');


                apparent_nVA_reg <=
                    (others => '0');


                apparent_result_mVA <=
                    (others => '0');


                pf_numerator_reg <=
                    (others => '0');


                pf_raw_reg <=
                    (others => '0');


                pf_over_unity_reg <=
                    '0';


                pf_low16_reg <=
                    (others => '0');


                pf_clamped_reg <=
                    (others => '0');


                pf_result_milli <=
                    (others => '0');


                active_power_mW <=
                    (others => '0');


                apparent_power_mVA <=
                    (others => '0');


                power_factor_milli <=
                    (others => '0');


                power_valid <=
                    '0';



            else


                power_valid <=
                    '0';


                instant_power_valid_reg <=
                    '0';



                ------------------------------------------------------
                -- Latch latest RMS pair
                ------------------------------------------------------

                if rms_valid_in = '1' then


                    rms_voltage_latched <=
                        voltage_rms_mV_in;


                    rms_current_latched <=
                        current_rms_uA_in;


                    rms_ready <=
                        '1';


                end if;



                ------------------------------------------------------
                -- INPUT MULTIPLIER PIPELINE
                ------------------------------------------------------

                if sample_valid_in = '1' then


                    instant_power_v :=
                        voltage_mV_in *
                        current_uA_in;


                    instant_power_reg <=
                        instant_power_v;



                    --------------------------------------------------
                    -- Positive-going voltage crossing
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


                    instant_power_valid_reg <=
                        '1';


                end if;



                ------------------------------------------------------
                -- CYCLE-SYNCHRONOUS POWER ACCUMULATION
                ------------------------------------------------------

                if instant_power_valid_reg = '1' then


                    if crossing_reg = '1' then


                        ------------------------------------------------
                        -- Capture the previous complete electrical
                        -- cycle.
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
                            power_cycle_ready = '0'
                        then


                            captured_power_sum_nW <=
                                power_sum_nW;


                            captured_sample_count <=
                                to_unsigned(
                                    cycle_sample_count,
                                    captured_sample_count'length
                                );


                            power_cycle_ready <=
                                '1';


                        end if;



                        ------------------------------------------------
                        -- Current crossing sample starts next cycle.
                        ------------------------------------------------

                        power_sum_nW <=
                            instant_power_reg;


                        cycle_sample_count <=
                            1;


                        cycle_started <=
                            '1';



                    elsif cycle_started = '1' then


                        power_sum_nW <=
                            power_sum_nW
                            +
                            instant_power_reg;


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
                    -- Wait until active-power cycle and RMS values
                    -- are both available.
                    --------------------------------------------------

                    when IDLE =>


                        if
                            power_cycle_ready = '1'
                            and
                            rms_ready = '1'
                        then


                            power_cycle_ready <=
                                '0';


                            state <=
                                ACTIVE_DIV_INIT;


                        end if;



                    --------------------------------------------------
                    -- Divide absolute cycle sum by actual cycle
                    -- sample count.
                    --------------------------------------------------

                    when ACTIVE_DIV_INIT =>


                        if captured_power_sum_nW < 0 then


                            active_negative <=
                                '1';


                            div_dividend <=
                                unsigned(
                                    -captured_power_sum_nW
                                );


                        else


                            active_negative <=
                                '0';


                            div_dividend <=
                                unsigned(
                                    captured_power_sum_nW
                                );


                        end if;


                        div_divisor <=
                            resize(
                                captured_sample_count,
                                64
                            );


                        div_quotient <=
                            (others => '0');


                        div_remainder <=
                            (others => '0');


                        div_bit_index <=
                            63;


                        state <=
                            ACTIVE_DIV_RUN;



                    --------------------------------------------------
                    -- Sequential active-power mean division
                    --------------------------------------------------

                    when ACTIVE_DIV_RUN =>


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


                            active_mean_nW <=
                                quotient_next;


                            state <=
                                ACTIVE_SCALE_INIT;


                        else


                            div_bit_index <=
                                div_bit_index - 1;


                        end if;



                    --------------------------------------------------
                    -- Initialize nW -> mW divide
                    --------------------------------------------------

                    when ACTIVE_SCALE_INIT =>


                        div_dividend <=
                            active_mean_nW;


                        div_divisor <=
                            to_unsigned(
                                1_000_000,
                                64
                            );


                        div_quotient <=
                            (others => '0');


                        div_remainder <=
                            (others => '0');


                        div_bit_index <=
                            63;


                        state <=
                            ACTIVE_SCALE_RUN;



                    --------------------------------------------------
                    -- nW -> mW divide
                    --------------------------------------------------

                    when ACTIVE_SCALE_RUN =>


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


                            active_abs_mW <=
                                quotient_next;


                            if active_negative = '1' then


                                active_result_mW <=
                                    -signed(
                                        quotient_next
                                    );


                            else


                                active_result_mW <=
                                    signed(
                                        quotient_next
                                    );


                            end if;


                            state <=
                                APPARENT_MUL;


                        else


                            div_bit_index <=
                                div_bit_index - 1;


                        end if;



                    --------------------------------------------------
                    -- Register apparent-power multiplication
                    --------------------------------------------------

                    when APPARENT_MUL =>


                        apparent_nVA_reg <=
                            rms_voltage_latched
                            *
                            rms_current_latched;


                        state <=
                            APPARENT_DIV_INIT;



                    --------------------------------------------------
                    -- Initialize apparent-power conversion
                    --------------------------------------------------

                    when APPARENT_DIV_INIT =>


                        div_dividend <=
                            apparent_nVA_reg;


                        div_divisor <=
                            to_unsigned(
                                1_000_000,
                                64
                            );


                        div_quotient <=
                            (others => '0');


                        div_remainder <=
                            (others => '0');


                        div_bit_index <=
                            63;


                        state <=
                            APPARENT_DIV_RUN;



                    --------------------------------------------------
                    -- Apparent-power sequential divide
                    --------------------------------------------------

                    when APPARENT_DIV_RUN =>


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


                            apparent_result_mVA <=
                                quotient_next;


                            state <=
                                PF_NUMERATOR;


                        else


                            div_bit_index <=
                                div_bit_index - 1;


                        end if;



                    --------------------------------------------------
                    -- Register PF numerator
                    --------------------------------------------------

                    when PF_NUMERATOR =>


                        pf_numerator_reg <=

                            shift_left(
                                active_abs_mW,
                                10
                            )

                            -

                            shift_left(
                                active_abs_mW,
                                4
                            )

                            -

                            shift_left(
                                active_abs_mW,
                                3
                            );


                        state <=
                            PF_DIV_INIT;



                    --------------------------------------------------
                    -- Initialize PF divider
                    --------------------------------------------------

                    when PF_DIV_INIT =>


                        if apparent_result_mVA = 0 then


                            pf_raw_reg <=
                                (others => '0');


                            state <=
                                PF_ANALYZE;


                        else


                            div_dividend <=
                                pf_numerator_reg;


                            div_divisor <=
                                apparent_result_mVA;


                            div_quotient <=
                                (others => '0');


                            div_remainder <=
                                (others => '0');


                            div_bit_index <=
                                63;


                            state <=
                                PF_DIV_RUN;


                        end if;



                    --------------------------------------------------
                    -- Sequential PF divide
                    --------------------------------------------------

                    when PF_DIV_RUN =>


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


                            pf_raw_reg <=
                                quotient_next;


                            state <=
                                PF_ANALYZE;


                        else


                            div_bit_index <=
                                div_bit_index - 1;


                        end if;



                    --------------------------------------------------
                    -- NEW PIPELINE STAGE 1
                    --
                    -- Wide comparison occurs here, but it only drives
                    -- a single registered flag.
                    --
                    -- Low 16 quotient bits are captured separately.
                    --------------------------------------------------

                    when PF_ANALYZE =>


                        if pf_raw_reg > 1000 then


                            pf_over_unity_reg <=
                                '1';


                        else


                            pf_over_unity_reg <=
                                '0';


                        end if;


                        pf_low16_reg <=
                            pf_raw_reg(
                                15 downto 0
                            );


                        state <=
                            PF_CLAMP;



                    --------------------------------------------------
                    -- NEW PIPELINE STAGE 2
                    --
                    -- Only a small 16-bit mux remains.
                    --------------------------------------------------

                    when PF_CLAMP =>


                        if pf_over_unity_reg = '1' then


                            pf_clamped_reg <=
                                to_unsigned(
                                    1000,
                                    16
                                );


                        else


                            pf_clamped_reg <=
                                pf_low16_reg;


                        end if;


                        state <=
                            PF_SIGN;



                    --------------------------------------------------
                    -- Sign restoration in separate clock
                    --------------------------------------------------

                    when PF_SIGN =>


                        if active_negative = '1' then


                            pf_result_milli <=
                                -signed(
                                    pf_clamped_reg
                                );


                        else


                            pf_result_milli <=
                                signed(
                                    pf_clamped_reg
                                );


                        end if;


                        state <=
                            OUTPUT_RESULT;



                    --------------------------------------------------
                    -- Publish complete P / S / PF measurement
                    --------------------------------------------------

                    when OUTPUT_RESULT =>


                        active_power_mW <=
                            resize(
                                active_result_mW,
                                32
                            );


                        apparent_power_mVA <=
                            resize(
                                apparent_result_mVA,
                                32
                            );


                        power_factor_milli <=
                            pf_result_milli;


                        power_valid <=
                            '1';


                        rms_ready <=
                            '0';


                        state <=
                            IDLE;



                    when others =>


                        state <=
                            IDLE;


                end case;


            end if;


        end if;


    end process;


end architecture rtl;