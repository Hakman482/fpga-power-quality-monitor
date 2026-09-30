library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity thd_1_25_meter is

    port (
        clk_100mhz : in std_logic;
        reset      : in std_logic;

        voltage_fund_mag_sq :
            in unsigned(79 downto 0);

        current_fund_mag_sq :
            in unsigned(79 downto 0);

        voltage_harm_sum_sq :
            in unsigned(84 downto 0);

        current_harm_sum_sq :
            in unsigned(84 downto 0);

        harmonic_valid_in :
            in std_logic;

        voltage_thd_x100 :
            out unsigned(15 downto 0);

        current_thd_x100 :
            out unsigned(15 downto 0);

        thd_valid :
            out std_logic
    );

end entity thd_1_25_meter;


architecture rtl of thd_1_25_meter is

    constant THD_AVERAGING_FRAMES :
        positive := 10;

    constant MULTIPLIER_100M :
        unsigned(26 downto 0) :=
        to_unsigned(100_000_000, 27);

    signal voltage_thd_frame :
        unsigned(15 downto 0) := (others => '0');

    signal current_thd_frame :
        unsigned(15 downto 0) := (others => '0');

    signal voltage_thd_sum :
        unsigned(19 downto 0) := (others => '0');

    signal current_thd_sum :
        unsigned(19 downto 0) := (others => '0');

    signal thd_frame_count :
        integer range 0 to THD_AVERAGING_FRAMES - 1 := 0;

    type state_type is (
        IDLE,
        CHANNEL_SETUP,
        MULTIPLY,
        DIV_SETUP,
        DIV_SHIFT,
        DIV_COMPARE,
        DIV_DONE,
        SQRT_SETUP,
        SQRT_RUN,
        SQRT_DONE,
        NEXT_CHANNEL
    );

    signal state :
        state_type := IDLE;

    signal channel_select :
        std_logic := '0';

    signal voltage_fund_reg :
        unsigned(79 downto 0) := (others => '0');

    signal current_fund_reg :
        unsigned(79 downto 0) := (others => '0');

    signal voltage_harm_reg :
        unsigned(84 downto 0) := (others => '0');

    signal current_harm_reg :
        unsigned(84 downto 0) := (others => '0');

    signal selected_fund :
        unsigned(79 downto 0) := (others => '0');

    signal selected_harm :
        unsigned(84 downto 0) := (others => '0');

    signal mult_accumulator :
        unsigned(111 downto 0) := (others => '0');

    signal mult_multiplicand :
        unsigned(111 downto 0) := (others => '0');

    signal mult_multiplier :
        unsigned(26 downto 0) := (others => '0');

    signal mult_count :
        integer range 0 to 26 := 0;

    signal dividend_reg :
        unsigned(111 downto 0) := (others => '0');

    signal divisor_reg :
        unsigned(111 downto 0) := (others => '0');

    signal quotient_reg :
        unsigned(111 downto 0) := (others => '0');

    signal remainder_reg :
        unsigned(112 downto 0) := (others => '0');

    signal trial_remainder_reg :
        unsigned(112 downto 0) := (others => '0');

    signal div_index :
        integer range 0 to 111 := 111;

    signal quotient_overflow :
        std_logic := '0';

    signal sqrt_input :
        unsigned(63 downto 0) := (others => '0');

    signal sqrt_root :
        unsigned(31 downto 0) := (others => '0');

    signal sqrt_remainder :
        unsigned(64 downto 0) := (others => '0');

    signal sqrt_pair_index :
        integer range 0 to 31 := 31;

begin

    process(clk_100mhz)

        variable shifted_remainder :
            unsigned(112 downto 0);

        variable divisor_extended :
            unsigned(112 downto 0);

        variable input_pair :
            unsigned(1 downto 0);

        variable sqrt_rem_next :
            unsigned(64 downto 0);

        variable sqrt_trial :
            unsigned(64 downto 0);

        variable sqrt_root_shift :
            unsigned(31 downto 0);

        variable sqrt_root_next :
            unsigned(31 downto 0);

        variable voltage_thd_total :
            unsigned(19 downto 0);

        variable current_thd_total :
            unsigned(19 downto 0);

    begin

        if rising_edge(clk_100mhz) then

            if reset = '1' then

                state <= IDLE;
                channel_select <= '0';

                voltage_thd_x100 <= (others => '0');
                current_thd_x100 <= (others => '0');

                voltage_thd_frame <= (others => '0');
                current_thd_frame <= (others => '0');

                voltage_thd_sum <= (others => '0');
                current_thd_sum <= (others => '0');

                thd_frame_count <= 0;
                thd_valid <= '0';

                voltage_fund_reg <= (others => '0');
                current_fund_reg <= (others => '0');

                voltage_harm_reg <= (others => '0');
                current_harm_reg <= (others => '0');

                selected_fund <= (others => '0');
                selected_harm <= (others => '0');

                mult_accumulator <= (others => '0');
                mult_multiplicand <= (others => '0');
                mult_multiplier <= (others => '0');
                mult_count <= 0;

                dividend_reg <= (others => '0');
                divisor_reg <= (others => '0');
                quotient_reg <= (others => '0');
                remainder_reg <= (others => '0');
                trial_remainder_reg <= (others => '0');

                div_index <= 111;
                quotient_overflow <= '0';

                sqrt_input <= (others => '0');
                sqrt_root <= (others => '0');
                sqrt_remainder <= (others => '0');
                sqrt_pair_index <= 31;

            else

                thd_valid <= '0';

                case state is

                    when IDLE =>

                        if harmonic_valid_in = '1' then

                            voltage_fund_reg <=
                                voltage_fund_mag_sq;

                            current_fund_reg <=
                                current_fund_mag_sq;

                            voltage_harm_reg <=
                                voltage_harm_sum_sq;

                            current_harm_reg <=
                                current_harm_sum_sq;

                            channel_select <= '0';
                            state <= CHANNEL_SETUP;

                        end if;

                    when CHANNEL_SETUP =>

                        if channel_select = '0' then

                            selected_fund <=
                                voltage_fund_reg;

                            selected_harm <=
                                voltage_harm_reg;

                        else

                            selected_fund <=
                                current_fund_reg;

                            selected_harm <=
                                current_harm_reg;

                        end if;

                        mult_accumulator <= (others => '0');
                        mult_multiplicand <= (others => '0');
                        mult_multiplier <= (others => '0');
                        mult_count <= 0;

                        state <= MULTIPLY;

                    when MULTIPLY =>

                        if mult_multiplier = 0 then

                            if selected_fund = 0 then

                                if channel_select = '0' then

                                    voltage_thd_frame <=
                                        (others => '0');

                                else

                                    current_thd_frame <=
                                        (others => '0');

                                end if;

                                state <= NEXT_CHANNEL;

                            else

                                mult_accumulator <=
                                    (others => '0');

                                mult_multiplicand <=
                                    resize(selected_harm, 112);

                                mult_multiplier <=
                                    MULTIPLIER_100M;

                                mult_count <= 0;

                            end if;

                        else

                            if mult_multiplier(0) = '1' then

                                mult_accumulator <=
                                    mult_accumulator +
                                    mult_multiplicand;

                            end if;

                            mult_multiplicand <=
                                shift_left(
                                    mult_multiplicand,
                                    1
                                );

                            mult_multiplier <=
                                shift_right(
                                    mult_multiplier,
                                    1
                                );

                            if mult_count = 26 then

                                mult_count <= 0;
                                state <= DIV_SETUP;

                            else

                                mult_count <=
                                    mult_count + 1;

                            end if;

                        end if;

                    when DIV_SETUP =>

                        dividend_reg <=
                            mult_accumulator;

                        divisor_reg <=
                            resize(selected_fund, 112);

                        quotient_reg <=
                            (others => '0');

                        remainder_reg <=
                            (others => '0');

                        trial_remainder_reg <=
                            (others => '0');

                        div_index <= 111;
                        quotient_overflow <= '0';

                        state <= DIV_SHIFT;

                    when DIV_SHIFT =>

                        shifted_remainder :=
                            shift_left(
                                remainder_reg,
                                1
                            );

                        shifted_remainder(0) :=
                            dividend_reg(div_index);

                        trial_remainder_reg <=
                            shifted_remainder;

                        state <= DIV_COMPARE;

                    when DIV_COMPARE =>

                        divisor_extended :=
                            resize(divisor_reg, 113);

                        if trial_remainder_reg >=
                           divisor_extended
                        then

                            remainder_reg <=
                                trial_remainder_reg -
                                divisor_extended;

                            quotient_reg(div_index) <=
                                '1';

                        else

                            remainder_reg <=
                                trial_remainder_reg;

                            quotient_reg(div_index) <=
                                '0';

                        end if;

                        if div_index = 0 then

                            state <= DIV_DONE;

                        else

                            div_index <=
                                div_index - 1;

                            state <= DIV_SHIFT;

                        end if;

                    when DIV_DONE =>

                        if quotient_reg(111 downto 64) /=
                           to_unsigned(0, 48)
                        then

                            quotient_overflow <= '1';
                            state <= SQRT_DONE;

                        else

                            quotient_overflow <= '0';

                            sqrt_input <=
                                quotient_reg(63 downto 0);

                            state <= SQRT_SETUP;

                        end if;

                    when SQRT_SETUP =>

                        sqrt_root <=
                            (others => '0');

                        sqrt_remainder <=
                            (others => '0');

                        sqrt_pair_index <= 31;

                        state <= SQRT_RUN;

                    when SQRT_RUN =>

                        input_pair :=
                            sqrt_input(
                                (2 * sqrt_pair_index) + 1
                                downto
                                2 * sqrt_pair_index
                            );

                        sqrt_rem_next :=
                            shift_left(
                                sqrt_remainder,
                                2
                            );

                        sqrt_rem_next(1 downto 0) :=
                            input_pair;

                        sqrt_root_shift :=
                            shift_left(
                                sqrt_root,
                                1
                            );

                        sqrt_trial :=
                            shift_left(
                                resize(sqrt_root, 65),
                                2
                            );

                        sqrt_trial :=
                            sqrt_trial +
                            to_unsigned(1, 65);

                        if sqrt_rem_next >= sqrt_trial then

                            sqrt_remainder <=
                                sqrt_rem_next -
                                sqrt_trial;

                            sqrt_root_next :=
                                sqrt_root_shift;

                            sqrt_root_next(0) :=
                                '1';

                        else

                            sqrt_remainder <=
                                sqrt_rem_next;

                            sqrt_root_next :=
                                sqrt_root_shift;

                        end if;

                        sqrt_root <=
                            sqrt_root_next;

                        if sqrt_pair_index = 0 then

                            state <= SQRT_DONE;

                        else

                            sqrt_pair_index <=
                                sqrt_pair_index - 1;

                        end if;

                    when SQRT_DONE =>

                        if quotient_overflow = '1' then

                            if channel_select = '0' then

                                voltage_thd_frame <=
                                    to_unsigned(65535, 16);

                            else

                                current_thd_frame <=
                                    to_unsigned(65535, 16);

                            end if;

                        elsif sqrt_root >
                              to_unsigned(65535, 32)
                        then

                            if channel_select = '0' then

                                voltage_thd_frame <=
                                    to_unsigned(65535, 16);

                            else

                                current_thd_frame <=
                                    to_unsigned(65535, 16);

                            end if;

                        else

                            if channel_select = '0' then

                                voltage_thd_frame <=
                                    resize(sqrt_root, 16);

                            else

                                current_thd_frame <=
                                    resize(sqrt_root, 16);

                            end if;

                        end if;

                        state <= NEXT_CHANNEL;

                    when NEXT_CHANNEL =>

                        mult_accumulator <=
                            (others => '0');

                        mult_multiplicand <=
                            (others => '0');

                        mult_multiplier <=
                            (others => '0');

                        mult_count <= 0;
                        quotient_overflow <= '0';

                        if channel_select = '0' then

                            channel_select <= '1';
                            state <= CHANNEL_SETUP;

                        else

                            channel_select <= '0';

                            voltage_thd_total :=
                                voltage_thd_sum +
                                resize(
                                    voltage_thd_frame,
                                    20
                                );

                            current_thd_total :=
                                current_thd_sum +
                                resize(
                                    current_thd_frame,
                                    20
                                );

                            if thd_frame_count =
                               THD_AVERAGING_FRAMES - 1
                            then

                                voltage_thd_x100 <=
                                    resize(
                                        voltage_thd_total /
                                        to_unsigned(
                                            THD_AVERAGING_FRAMES,
                                            20
                                        ),
                                        16
                                    );

                                current_thd_x100 <=
                                    resize(
                                        current_thd_total /
                                        to_unsigned(
                                            THD_AVERAGING_FRAMES,
                                            20
                                        ),
                                        16
                                    );

                                voltage_thd_sum <=
                                    (others => '0');

                                current_thd_sum <=
                                    (others => '0');

                                thd_frame_count <= 0;
                                thd_valid <= '1';

                            else

                                voltage_thd_sum <=
                                    voltage_thd_total;

                                current_thd_sum <=
                                    current_thd_total;

                                thd_frame_count <=
                                    thd_frame_count + 1;

                            end if;

                            state <= IDLE;

                        end if;

                end case;

            end if;

        end if;

    end process;

end architecture rtl;