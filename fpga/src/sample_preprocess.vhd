library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sample_preprocess is

    port (

        --------------------------------------------------------------
        -- FPGA system signals
        --------------------------------------------------------------
        clk_100mhz : in std_logic;
        reset      : in std_logic;

        --------------------------------------------------------------
        -- Raw synchronized ADS8320 samples
        --------------------------------------------------------------
        voltage_raw : in std_logic_vector(15 downto 0);
        current_raw : in std_logic_vector(15 downto 0);

        sample_valid_in : in std_logic;

        --------------------------------------------------------------
        -- Signed zero-centred samples
        --------------------------------------------------------------
        voltage_signed : out signed(16 downto 0);
        current_signed : out signed(16 downto 0);

        --------------------------------------------------------------
        -- Output-valid pulse
        --------------------------------------------------------------
        sample_valid_out : out std_logic

    );

end entity sample_preprocess;


architecture rtl of sample_preprocess is

    --------------------------------------------------------------
    -- Measured zero-input ADC codes.
    -- Separate values are required because the two analogue channels
    -- have different measured DC offsets.
    --------------------------------------------------------------

    constant VOLTAGE_ZERO_CODE :
        signed(16 downto 0) := to_signed(32809, 17);

    constant CURRENT_ZERO_CODE :
        signed(16 downto 0) := to_signed(32359, 17);

begin


    preprocess_proc : process(clk_100mhz)

        variable voltage_ext : signed(16 downto 0);
        variable current_ext : signed(16 downto 0);

    begin

        if rising_edge(clk_100mhz) then

            if reset = '1' then

                voltage_signed  <= (others => '0');
                current_signed  <= (others => '0');

                sample_valid_out <= '0';


            else

                ------------------------------------------------------
                -- Default:
                -- output-valid is only one clock wide
                ------------------------------------------------------

                sample_valid_out <= '0';


                ------------------------------------------------------
                -- Only process when a new synchronized ADC pair
                -- arrives
                ------------------------------------------------------

                if sample_valid_in = '1' then

                    --------------------------------------------------
                    -- Extend unsigned 16-bit ADC values to 17 bits
                    -- before subtraction.
                    --------------------------------------------------

                    voltage_ext :=
                        signed('0' & voltage_raw);

                    current_ext :=
                        signed('0' & current_raw);


                    --------------------------------------------------
                    -- Remove the measured zero-input offset for each
                    -- analogue channel.
                    --------------------------------------------------

                    voltage_signed <=
                        voltage_ext - VOLTAGE_ZERO_CODE;

                    current_signed <=
                        current_ext - CURRENT_ZERO_CODE;


                    --------------------------------------------------
                    -- New processed sample pair is ready
                    --------------------------------------------------

                    sample_valid_out <= '1';

                end if;

            end if;

        end if;

    end process;


end architecture rtl;