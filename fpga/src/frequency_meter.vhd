library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity frequency_meter is

    generic (
        SYS_CLK_HZ : positive := 100_000_000
    );

    port (
        clk_100mhz : in std_logic;
        reset      : in std_logic;

        voltage_mV_in  : in signed(31 downto 0);
        sample_valid_in : in std_logic;

        frequency_mHz   : out unsigned(31 downto 0);
        frequency_valid : out std_logic
    );

end entity frequency_meter;


architecture rtl of frequency_meter is

    constant POSITIVE_THRESHOLD_MV :
        signed(31 downto 0) := to_signed(500, 32);

    constant NEGATIVE_THRESHOLD_MV :
        signed(31 downto 0) := to_signed(-500, 32);

    constant MIN_PERIOD_CLOCKS :
        unsigned(31 downto 0) :=
        to_unsigned(SYS_CLK_HZ / 55, 32);

    constant MAX_PERIOD_CLOCKS :
        unsigned(31 downto 0) :=
        to_unsigned(SYS_CLK_HZ / 45, 32);

    constant NO_SIGNAL_TIMEOUT_CLOCKS :
        unsigned(31 downto 0) :=
        to_unsigned(SYS_CLK_HZ / 10, 32);

    constant AVERAGING_PERIODS :
        positive := 5;

    signal positive_crossing_armed :
        std_logic := '0';

    signal period_counter :
        unsigned(31 downto 0) := (others => '0');

    signal first_crossing_seen :
        std_logic := '0';

    signal accumulated_period_clocks :
        unsigned(31 downto 0) := (others => '0');

    signal accumulated_period_count :
        integer range 0 to AVERAGING_PERIODS - 1 := 0;

    signal divider_busy :
        std_logic := '0';

    signal dividend_reg :
        unsigned(63 downto 0) := (others => '0');

    signal divisor_reg :
        unsigned(31 downto 0) := (others => '0');

    signal quotient_reg :
        unsigned(63 downto 0) := (others => '0');

    signal remainder_reg :
        unsigned(64 downto 0) := (others => '0');

    signal div_bit_index :
        integer range 0 to 63 := 63;


    function multiply_by_1000 (
        value_in : unsigned(63 downto 0)
    ) return unsigned is

        variable result_value :
            unsigned(63 downto 0);

    begin

        result_value :=
              shift_left(value_in, 10)
            - shift_left(value_in, 4)
            - shift_left(value_in, 3);

        return result_value;

    end function;


begin

    frequency_process : process(clk_100mhz)

        variable period_clocks :
            unsigned(31 downto 0);

        variable total_period_clocks :
            unsigned(31 downto 0);

        variable sysclk_64 :
            unsigned(63 downto 0);

        variable numerator_64 :
            unsigned(63 downto 0);

        variable remainder_shifted :
            unsigned(64 downto 0);

        variable divisor_extended :
            unsigned(64 downto 0);

        variable quotient_next :
            unsigned(63 downto 0);

    begin

        if rising_edge(clk_100mhz) then

            if reset = '1' then

                positive_crossing_armed <=
                    '0';

                period_counter <=
                    (others => '0');

                first_crossing_seen <=
                    '0';

                accumulated_period_clocks <=
                    (others => '0');

                accumulated_period_count <=
                    0;

                frequency_mHz <=
                    (others => '0');

                frequency_valid <=
                    '0';

                divider_busy <=
                    '0';

                dividend_reg <=
                    (others => '0');

                divisor_reg <=
                    (others => '0');

                quotient_reg <=
                    (others => '0');

                remainder_reg <=
                    (others => '0');

                div_bit_index <=
                    63;

            else

                frequency_valid <=
                    '0';

                ------------------------------------------------------
                -- Period counter
                ------------------------------------------------------
                if first_crossing_seen = '1' then

                    period_counter <=
                        period_counter + 1;

                    --------------------------------------------------
                    -- Clear frequency after 100 ms without a valid
                    -- positive-going crossing.
                    --------------------------------------------------
                    if period_counter >= NO_SIGNAL_TIMEOUT_CLOCKS then

                        period_counter <=
                            (others => '0');

                        first_crossing_seen <=
                            '0';

                        positive_crossing_armed <=
                            '0';

                        accumulated_period_clocks <=
                            (others => '0');

                        accumulated_period_count <=
                            0;

                        frequency_mHz <=
                            (others => '0');

                        frequency_valid <=
                            '1';

                    end if;

                end if;

                ------------------------------------------------------
                -- Hysteretic positive-going crossing detector
                ------------------------------------------------------
                if sample_valid_in = '1' then

                    if voltage_mV_in <= NEGATIVE_THRESHOLD_MV then

                        positive_crossing_armed <=
                            '1';

                    end if;

                    if
                        (positive_crossing_armed = '1') and
                        (voltage_mV_in >= POSITIVE_THRESHOLD_MV)
                    then

                        positive_crossing_armed <=
                            '0';

                        ------------------------------------------------
                        -- First crossing establishes the reference
                        ------------------------------------------------
                        if first_crossing_seen = '0' then

                            first_crossing_seen <=
                                '1';

                            period_counter <=
                                (others => '0');

                        else

                            period_clocks :=
                                period_counter;

                            ------------------------------------------------
                            -- Accept only periods from 45 Hz to 55 Hz
                            ------------------------------------------------
                            if
                                (period_clocks >= MIN_PERIOD_CLOCKS) and
                                (period_clocks <= MAX_PERIOD_CLOCKS)
                            then

                                period_counter <=
                                    (others => '0');

                                total_period_clocks :=
                                    accumulated_period_clocks +
                                    period_clocks;

                                ------------------------------------------------
                                -- Publish after five valid periods
                                ------------------------------------------------
                                if accumulated_period_count =
                                   AVERAGING_PERIODS - 1
                                then

                                    accumulated_period_clocks <=
                                        (others => '0');

                                    accumulated_period_count <=
                                        0;

                                    if divider_busy = '0' then

                                        sysclk_64 :=
                                            to_unsigned(
                                                SYS_CLK_HZ,
                                                64
                                            );

                                        numerator_64 :=
                                            multiply_by_1000(
                                                sysclk_64
                                            );

                                        ------------------------------------------------
                                        -- Multiply numerator by five
                                        ------------------------------------------------
                                        numerator_64 :=
                                            shift_left(
                                                numerator_64,
                                                2
                                            ) + numerator_64;

                                        dividend_reg <=
                                            numerator_64;

                                        divisor_reg <=
                                            total_period_clocks;

                                        quotient_reg <=
                                            (others => '0');

                                        remainder_reg <=
                                            (others => '0');

                                        div_bit_index <=
                                            63;

                                        divider_busy <=
                                            '1';

                                    end if;

                                else

                                    accumulated_period_clocks <=
                                        total_period_clocks;

                                    accumulated_period_count <=
                                        accumulated_period_count + 1;

                                end if;

                            ------------------------------------------------
                            -- Period is too long: reacquire
                            ------------------------------------------------
                            elsif period_clocks > MAX_PERIOD_CLOCKS then

                                period_counter <=
                                    (others => '0');

                                accumulated_period_clocks <=
                                    (others => '0');

                                accumulated_period_count <=
                                    0;

                            ------------------------------------------------
                            -- Period is too short: ignore it
                            ------------------------------------------------
                            else

                                null;

                            end if;

                        end if;

                    end if;

                end if;

                ------------------------------------------------------
                -- Sequential restoring divider
                ------------------------------------------------------
                if divider_busy = '1' then

                    remainder_shifted :=
                        shift_left(
                            remainder_reg,
                            1
                        );

                    remainder_shifted(0) :=
                        dividend_reg(div_bit_index);

                    divisor_extended :=
                        resize(
                            divisor_reg,
                            65
                        );

                    quotient_next :=
                        quotient_reg;

                    if remainder_shifted >= divisor_extended then

                        remainder_reg <=
                            remainder_shifted -
                            divisor_extended;

                        quotient_next(div_bit_index) :=
                            '1';

                    else

                        remainder_reg <=
                            remainder_shifted;

                        quotient_next(div_bit_index) :=
                            '0';

                    end if;

                    quotient_reg <=
                        quotient_next;

                    if div_bit_index = 0 then

                        frequency_mHz <=
                            resize(
                                quotient_next,
                                frequency_mHz'length
                            );

                        frequency_valid <=
                            '1';

                        divider_busy <=
                            '0';

                        div_bit_index <=
                            63;

                    else

                        div_bit_index <=
                            div_bit_index - 1;

                    end if;

                end if;

            end if;

        end if;

    end process;

end architecture rtl;