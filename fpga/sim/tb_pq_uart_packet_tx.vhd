library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity tb_pq_uart_packet_tx is
end entity;


architecture sim of tb_pq_uart_packet_tx is

    constant CLK_PERIOD : time := 10 ns;

    -- Keep the frame deliberately small for simulation.
    constant C_SAMPLE_RATE_HZ       : positive := 10_000;
    constant C_SAMPLE_FRAME_SAMPLES : positive := 4;
    constant C_FRAME_PERIOD_SAMPLES : positive := 6;

    signal clk_100mhz : std_logic := '0';
    signal reset      : std_logic := '1';

    signal voltage_mV_in : signed(31 downto 0) := (others => '0');
    signal current_uA_in : signed(31 downto 0) := (others => '0');
    signal voltage_raw_in : std_logic_vector(15 downto 0) := (others => '0');
    signal current_raw_in : std_logic_vector(15 downto 0) := (others => '0');
    signal sample_valid  : std_logic := '0';

    signal voltage_rms_mV     : unsigned(31 downto 0) := to_unsigned(230_000, 32);
    signal current_rms_uA     : unsigned(31 downto 0) := to_unsigned(1_250_000, 32);
    signal frequency_mHz      : unsigned(31 downto 0) := to_unsigned(50_000, 32);
    signal active_power_mW    : signed(31 downto 0)   := to_signed(250_000, 32);
    signal apparent_power_mVA : unsigned(31 downto 0) := to_unsigned(287_500, 32);
    signal power_factor_milli : signed(15 downto 0)   := to_signed(870, 16);
    signal voltage_thd_x100   : unsigned(15 downto 0) := to_unsigned(325, 16);
    signal current_thd_x100   : unsigned(15 downto 0) := to_unsigned(575, 16);
    signal metric_trigger     : std_logic := '0';

    signal uart_busy  : std_logic := '0';
    signal uart_data  : std_logic_vector(7 downto 0);
    signal uart_start : std_logic;
    signal packet_busy : std_logic;

    type byte_array_t is array (natural range <>) of std_logic_vector(7 downto 0);

    constant EXPECTED_METRIC : byte_array_t(0 to 27) := (
        x"AA", x"55",

        -- Vrms = 230000 mV = 0x00038270
        x"00", x"03", x"82", x"70",

        -- Irms = 1250000 uA = 0x001312D0
        x"00", x"13", x"12", x"D0",

        -- Frequency = 50000 mHz = 0x0000C350
        x"00", x"00", x"C3", x"50",

        -- P = 250000 mW = 0x0003D090
        x"00", x"03", x"D0", x"90",

        -- S = 287500 mVA = 0x0004630C
        x"00", x"04", x"63", x"0C",

        -- PF = 870 = 0x0366
        x"03", x"66",

        -- THD-V = 325 = 0x0145
        x"01", x"45",

        -- THD-I = 575 = 0x023F
        x"02", x"3F"
    );


    procedure wait_clocks(
        signal clk : in std_logic;
        constant n : in positive
    ) is
    begin
        for k in 1 to n loop
            wait until rising_edge(clk);
        end loop;
    end procedure;


begin

    clk_100mhz <= not clk_100mhz after CLK_PERIOD/2;


    DUT :
        entity work.pq_uart_packet_tx
        generic map (
            SAMPLE_RATE_HZ       => C_SAMPLE_RATE_HZ,
            SAMPLE_FRAME_SAMPLES => C_SAMPLE_FRAME_SAMPLES,
            FRAME_PERIOD_SAMPLES => C_FRAME_PERIOD_SAMPLES
        )
        port map (
            clk_100mhz => clk_100mhz,
            reset      => reset,

            voltage_raw_in => voltage_raw_in,
            current_raw_in => current_raw_in,
            voltage_mV_in  => voltage_mV_in,
            current_uA_in  => current_uA_in,
            sample_valid   => sample_valid,

            voltage_rms_mV     => voltage_rms_mV,
            current_rms_uA     => current_rms_uA,
            frequency_mHz      => frequency_mHz,
            active_power_mW    => active_power_mW,
            apparent_power_mVA => apparent_power_mVA,
            power_factor_milli => power_factor_milli,
            voltage_thd_x100   => voltage_thd_x100,
            current_thd_x100   => current_thd_x100,
            metric_trigger     => metric_trigger,

            uart_busy  => uart_busy,
            uart_data  => uart_data,
            uart_start => uart_start,

            packet_busy => packet_busy
        );


    ------------------------------------------------------------------
    -- UART transmitter handshake model.
    --
    -- When uart_start pulses, hold uart_busy high for a few clocks.
    -- This verifies that the packet formatter waits for the byte to
    -- finish before advancing.
    ------------------------------------------------------------------
    UART_BUSY_MODEL :
        process
    begin
        uart_busy <= '0';

        wait until reset = '0';

        loop
            wait until rising_edge(clk_100mhz);

            if uart_start = '1' then
                uart_busy <= '1';

                wait_clocks(clk_100mhz, 4);

                uart_busy <= '0';
            end if;
        end loop;
    end process;


    ------------------------------------------------------------------
    -- Stimulus
    ------------------------------------------------------------------
    STIMULUS :
        process
    begin

        wait_clocks(clk_100mhz, 5);
        reset <= '0';

        wait_clocks(clk_100mhz, 5);


        --------------------------------------------------------------
        -- Trigger one AA55 metric packet.
        --------------------------------------------------------------
        metric_trigger <= '1';
        wait until rising_edge(clk_100mhz);
        metric_trigger <= '0';


        --------------------------------------------------------------
        -- Feed enough valid samples to trigger a 4-sample frame.
        --
        -- FRAME_PERIOD_SAMPLES = 6:
        -- first 6 valid samples count toward the period,
        -- then the next 4 are captured.
        --------------------------------------------------------------
        for k in 0 to 12 loop

            voltage_mV_in <=
                to_signed(
                    (k + 1) * 1000,
                    32
                );

            current_uA_in <=
                to_signed(
                    (k + 1) * 100000,
                    32
                );

            voltage_raw_in <=
                std_logic_vector(to_unsigned(1000 + k, 16));

            current_raw_in <=
                std_logic_vector(to_unsigned(2000 + k, 16));

            sample_valid <= '1';

            wait until rising_edge(clk_100mhz);

            sample_valid <= '0';

            wait_clocks(clk_100mhz, 2);

        end loop;


        --------------------------------------------------------------
        -- Allow all queued bytes to transmit.
        --------------------------------------------------------------
        wait for 100 us;


        assert false
            report "tb_pq_uart_packet_tx completed successfully."
            severity failure;

    end process;


    ------------------------------------------------------------------
    -- Check the first complete packet byte-for-byte.
    ------------------------------------------------------------------
    METRIC_CHECKER :
        process

        variable index :
            integer := 0;

    begin

        wait until reset = '0';

        while index <= 27 loop

            wait until rising_edge(clk_100mhz);

            if uart_start = '1' then

                assert uart_data = EXPECTED_METRIC(index)
                    report
                        "Metric packet mismatch at byte " &
                        integer'image(index)
                    severity error;

                index :=
                    index + 1;

            end if;

        end loop;


        report
            "AA55 metric packet PASS"
            severity note;

        wait;

    end process;


    ------------------------------------------------------------------
    -- Find and validate one AA56 sample frame.
    ------------------------------------------------------------------
    SAMPLE_CHECKER :
        process

        type int_array_t is array (0 to C_SAMPLE_FRAME_SAMPLES-1) of integer;

        variable sample_voltage_expected :
            int_array_t := (
                6000,
                7000,
                8000,
                9000
            );

        variable sample_current_expected :
            int_array_t := (
                600000,
                700000,
                800000,
                900000
            );

        variable sample_voltage_raw_expected :
            int_array_t := (
                1005,
                1006,
                1007,
                1008
            );

        variable sample_current_raw_expected :
            int_array_t := (
                2005,
                2006,
                2007,
                2008
            );

        variable byte_count :
            integer := 0;

        variable state :
            integer := 0;

        variable count_value :
            integer := 0;

        variable fs_value :
            integer := 0;

        variable sequence_value :
            integer := 0;

        variable sample_index :
            integer := 0;

        variable pair_byte :
            integer := 0;

        variable v_acc :
            signed(31 downto 0) := (others => '0');

        variable i_acc :
            signed(31 downto 0) := (others => '0');

        variable v_raw_acc :
            unsigned(15 downto 0) := (others => '0');

        variable i_raw_acc :
            unsigned(15 downto 0) := (others => '0');

        variable b :
            std_logic_vector(7 downto 0);

    begin

        wait until reset = '0';


        --------------------------------------------------------------
        -- Skip bytes until AA56 appears.
        --------------------------------------------------------------
        loop

            wait until rising_edge(clk_100mhz);

            if uart_start = '1' then

                if state = 0 then

                    if uart_data = x"AA" then
                        state := 1;
                    end if;


                elsif state = 1 then

                    if uart_data = x"56" then
                        exit;
                    elsif uart_data = x"AA" then
                        state := 1;
                    else
                        state := 0;
                    end if;

                end if;

            end if;

        end loop;


        --------------------------------------------------------------
        -- Version
        --------------------------------------------------------------
        loop
            wait until rising_edge(clk_100mhz);
            exit when uart_start = '1';
        end loop;

        assert uart_data = x"02"
            report "AA56 protocol version mismatch"
            severity error;


        --------------------------------------------------------------
        -- Sample count u16
        --------------------------------------------------------------
        loop
            wait until rising_edge(clk_100mhz);
            exit when uart_start = '1';
        end loop;

        count_value :=
            to_integer(unsigned(uart_data)) * 256;

        loop
            wait until rising_edge(clk_100mhz);
            exit when uart_start = '1';
        end loop;

        count_value :=
            count_value +
            to_integer(unsigned(uart_data));

        assert count_value = C_SAMPLE_FRAME_SAMPLES
            report "AA56 sample count mismatch"
            severity error;


        --------------------------------------------------------------
        -- Sample rate u32
        --------------------------------------------------------------
        fs_value := 0;

        for n in 0 to 3 loop

            loop
                wait until rising_edge(clk_100mhz);
                exit when uart_start = '1';
            end loop;

            fs_value :=
                fs_value * 256 +
                to_integer(unsigned(uart_data));

        end loop;

        assert fs_value = C_SAMPLE_RATE_HZ
            report "AA56 sample rate mismatch"
            severity error;


        --------------------------------------------------------------
        -- Sequence u16
        --------------------------------------------------------------
        sequence_value := 0;

        for n in 0 to 1 loop

            loop
                wait until rising_edge(clk_100mhz);
                exit when uart_start = '1';
            end loop;

            sequence_value :=
                sequence_value * 256 +
                to_integer(unsigned(uart_data));

        end loop;


        --------------------------------------------------------------
        -- Repeated V/I pairs.
        --------------------------------------------------------------
        for s in 0 to C_SAMPLE_FRAME_SAMPLES-1 loop

            v_raw_acc :=
                (others => '0');

            i_raw_acc :=
                (others => '0');

            v_acc :=
                (others => '0');

            i_acc :=
                (others => '0');


            for n in 0 to 1 loop

                loop
                    wait until rising_edge(clk_100mhz);
                    exit when uart_start = '1';
                end loop;

                v_raw_acc := shift_left(v_raw_acc, 8);
                v_raw_acc(7 downto 0) := unsigned(uart_data);

            end loop;


            for n in 0 to 1 loop

                loop
                    wait until rising_edge(clk_100mhz);
                    exit when uart_start = '1';
                end loop;

                i_raw_acc := shift_left(i_raw_acc, 8);
                i_raw_acc(7 downto 0) := unsigned(uart_data);

            end loop;


            for n in 0 to 3 loop

                loop
                    wait until rising_edge(clk_100mhz);
                    exit when uart_start = '1';
                end loop;

                b := uart_data;

                v_acc :=
                    shift_left(
                        v_acc,
                        8
                    );

                v_acc(7 downto 0) :=
                    signed(b);

            end loop;


            for n in 0 to 3 loop

                loop
                    wait until rising_edge(clk_100mhz);
                    exit when uart_start = '1';
                end loop;

                b := uart_data;

                i_acc :=
                    shift_left(
                        i_acc,
                        8
                    );

                i_acc(7 downto 0) :=
                    signed(b);

            end loop;


            assert to_integer(v_acc) =
                sample_voltage_expected(s)
                report
                    "AA56 voltage mismatch at sample " &
                    integer'image(s)
                severity error;


            assert to_integer(v_raw_acc) =
                sample_voltage_raw_expected(s)
                report
                    "AA56 raw voltage mismatch at sample " &
                    integer'image(s)
                severity error;


            assert to_integer(i_raw_acc) =
                sample_current_raw_expected(s)
                report
                    "AA56 raw current mismatch at sample " &
                    integer'image(s)
                severity error;


            assert to_integer(i_acc) =
                sample_current_expected(s)
                report
                    "AA56 current mismatch at sample " &
                    integer'image(s)
                severity error;

        end loop;


        report
            "AA56 sample packet PASS"
            severity note;

        wait;

    end process;


end architecture;
