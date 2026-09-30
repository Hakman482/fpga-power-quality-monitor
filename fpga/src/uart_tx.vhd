library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_tx is

    generic (
        CLK_FREQ_HZ : positive := 100_000_000;
        BAUD_RATE   : positive := 115_200
    );

    port (
        clk_100mhz : in  std_logic;
        reset      : in  std_logic;

        tx_data    : in  std_logic_vector(7 downto 0);
        tx_start   : in  std_logic;

        tx         : out std_logic;
        tx_busy    : out std_logic
    );

end entity uart_tx;


architecture rtl of uart_tx is

    constant CLKS_PER_BIT :
        positive := CLK_FREQ_HZ / BAUD_RATE;

    type state_type is (
        IDLE,
        START_BIT,
        DATA_BITS,
        STOP_BIT
    );

    signal state :
        state_type := IDLE;

    signal baud_counter :
        integer range 0 to CLKS_PER_BIT - 1 := 0;

    signal bit_index :
        integer range 0 to 7 := 0;

    signal data_reg :
        std_logic_vector(7 downto 0) :=
        (others => '0');

    signal tx_reg :
        std_logic := '1';

    signal busy_reg :
        std_logic := '0';

begin

    tx <= tx_reg;
    tx_busy <= busy_reg;


    process(clk_100mhz)
    begin

        if rising_edge(clk_100mhz) then

            if reset = '1' then

                state <= IDLE;

                baud_counter <= 0;
                bit_index <= 0;

                data_reg <=
                    (others => '0');

                tx_reg <= '1';
                busy_reg <= '0';


            else

                case state is


                    --------------------------------------------------
                    -- Waiting for a byte
                    --------------------------------------------------
                    when IDLE =>

                        tx_reg <= '1';
                        busy_reg <= '0';

                        baud_counter <= 0;
                        bit_index <= 0;

                        if tx_start = '1' then

                            data_reg <= tx_data;

                            busy_reg <= '1';

                            state <= START_BIT;

                        end if;


                    --------------------------------------------------
                    -- Start bit = 0
                    --------------------------------------------------
                    when START_BIT =>

                        tx_reg <= '0';
                        busy_reg <= '1';

                        if baud_counter =
                            CLKS_PER_BIT - 1 then

                            baud_counter <= 0;

                            state <= DATA_BITS;

                        else

                            baud_counter <=
                                baud_counter + 1;

                        end if;


                    --------------------------------------------------
                    -- 8 data bits
                    -- LSB first
                    --------------------------------------------------
                    when DATA_BITS =>

                        tx_reg <=
                            data_reg(bit_index);

                        busy_reg <= '1';

                        if baud_counter =
                            CLKS_PER_BIT - 1 then

                            baud_counter <= 0;

                            if bit_index = 7 then

                                bit_index <= 0;

                                state <= STOP_BIT;

                            else

                                bit_index <=
                                    bit_index + 1;

                            end if;

                        else

                            baud_counter <=
                                baud_counter + 1;

                        end if;


                    --------------------------------------------------
                    -- Stop bit = 1
                    --------------------------------------------------
                    when STOP_BIT =>

                        tx_reg <= '1';
                        busy_reg <= '1';

                        if baud_counter =
                            CLKS_PER_BIT - 1 then

                            baud_counter <= 0;

                            busy_reg <= '0';

                            state <= IDLE;

                        else

                            baud_counter <=
                                baud_counter + 1;

                        end if;


                end case;

            end if;

        end if;

    end process;

end architecture rtl;