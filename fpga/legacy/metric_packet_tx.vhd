library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity metric_packet_tx is

    port (

        --------------------------------------------------------------
        -- FPGA
        --------------------------------------------------------------
        clk_100mhz : in std_logic;
        reset      : in std_logic;


        --------------------------------------------------------------
        -- Measurement results
        --------------------------------------------------------------
        voltage_rms_mV :
            in unsigned(31 downto 0);

        current_rms_uA :
            in unsigned(31 downto 0);

        frequency_mHz :
            in unsigned(31 downto 0);

        active_power_mW :
            in signed(31 downto 0);

        apparent_power_mVA :
            in unsigned(31 downto 0);

        power_factor_milli :
            in signed(15 downto 0);

        voltage_thd_x100 :
            in unsigned(15 downto 0);

        current_thd_x100 :
            in unsigned(15 downto 0);


        --------------------------------------------------------------
        -- THD diagnostic
        --
        -- Actual number of samples in the electrical-cycle frame
        -- used by the harmonic/THD processor.
        --------------------------------------------------------------
        thd_frame_samples :
            in unsigned(15 downto 0);


        --------------------------------------------------------------
        -- Trigger
        --------------------------------------------------------------
        packet_trigger :
            in std_logic;


        --------------------------------------------------------------
        -- UART interface
        --------------------------------------------------------------
        uart_busy :
            in std_logic;

        uart_data :
            out std_logic_vector(7 downto 0);

        uart_start :
            out std_logic;


        --------------------------------------------------------------
        -- Status
        --------------------------------------------------------------
        packet_busy :
            out std_logic

    );

end entity metric_packet_tx;



architecture rtl of metric_packet_tx is


    ------------------------------------------------------------------
    -- Packet:
    --
    -- Byte  0 : AA
    -- Byte  1 : 55
    --
    -- Bytes  2..5  : Vrms
    -- Bytes  6..9  : Irms
    -- Bytes 10..13 : Frequency
    -- Bytes 14..17 : Active power
    -- Bytes 18..21 : Apparent power
    -- Bytes 22..23 : Power factor
    -- Bytes 24..25 : Voltage THD
    -- Bytes 26..27 : Current THD
    -- Bytes 28..29 : THD frame sample count
    --
    -- Multi-byte quantities are transmitted MSB first.
    ------------------------------------------------------------------

    constant PACKET_LENGTH :
        integer := 30;



    ------------------------------------------------------------------
    -- Captured metric registers
    ------------------------------------------------------------------

    signal vrms_reg :
        unsigned(31 downto 0) :=
        (others => '0');


    signal irms_reg :
        unsigned(31 downto 0) :=
        (others => '0');


    signal frequency_reg :
        unsigned(31 downto 0) :=
        (others => '0');


    signal active_power_reg :
        signed(31 downto 0) :=
        (others => '0');


    signal apparent_power_reg :
        unsigned(31 downto 0) :=
        (others => '0');


    signal power_factor_reg :
        signed(15 downto 0) :=
        (others => '0');


    signal voltage_thd_reg :
        unsigned(15 downto 0) :=
        (others => '0');


    signal current_thd_reg :
        unsigned(15 downto 0) :=
        (others => '0');


    --------------------------------------------------------------
    -- NEW diagnostic snapshot register
    --------------------------------------------------------------

    signal thd_frame_samples_reg :
        unsigned(15 downto 0) :=
        (others => '0');



    ------------------------------------------------------------------
    -- State machine
    ------------------------------------------------------------------

    type state_type is (

        IDLE,
        SEND_BYTE,
        WAIT_BUSY,
        WAIT_DONE

    );


    signal state :
        state_type :=
        IDLE;


    signal byte_index :
        integer range 0 to PACKET_LENGTH - 1 :=
        0;


    signal uart_data_reg :
        std_logic_vector(7 downto 0) :=
        (others => '0');


    signal uart_start_reg :
        std_logic :=
        '0';


    signal packet_busy_reg :
        std_logic :=
        '0';



    ------------------------------------------------------------------
    -- Packet-byte selection function
    ------------------------------------------------------------------

    function get_packet_byte (

        index_value :
            integer;

        vrms_value :
            unsigned(31 downto 0);

        irms_value :
            unsigned(31 downto 0);

        frequency_value :
            unsigned(31 downto 0);

        active_power_value :
            signed(31 downto 0);

        apparent_power_value :
            unsigned(31 downto 0);

        power_factor_value :
            signed(15 downto 0);

        voltage_thd_value :
            unsigned(15 downto 0);

        current_thd_value :
            unsigned(15 downto 0);

        thd_frame_samples_value :
            unsigned(15 downto 0)

    )
    return std_logic_vector is


        variable result :
            std_logic_vector(7 downto 0);


    begin


        result :=
            (others => '0');


        case index_value is


            ----------------------------------------------------------
            -- Header
            ----------------------------------------------------------

            when 0 =>

                result :=
                    x"AA";


            when 1 =>

                result :=
                    x"55";



            ----------------------------------------------------------
            -- Voltage RMS
            ----------------------------------------------------------

            when 2 =>

                result :=
                    std_logic_vector(
                        vrms_value(31 downto 24)
                    );


            when 3 =>

                result :=
                    std_logic_vector(
                        vrms_value(23 downto 16)
                    );


            when 4 =>

                result :=
                    std_logic_vector(
                        vrms_value(15 downto 8)
                    );


            when 5 =>

                result :=
                    std_logic_vector(
                        vrms_value(7 downto 0)
                    );



            ----------------------------------------------------------
            -- Current RMS
            ----------------------------------------------------------

            when 6 =>

                result :=
                    std_logic_vector(
                        irms_value(31 downto 24)
                    );


            when 7 =>

                result :=
                    std_logic_vector(
                        irms_value(23 downto 16)
                    );


            when 8 =>

                result :=
                    std_logic_vector(
                        irms_value(15 downto 8)
                    );


            when 9 =>

                result :=
                    std_logic_vector(
                        irms_value(7 downto 0)
                    );



            ----------------------------------------------------------
            -- Frequency
            ----------------------------------------------------------

            when 10 =>

                result :=
                    std_logic_vector(
                        frequency_value(31 downto 24)
                    );


            when 11 =>

                result :=
                    std_logic_vector(
                        frequency_value(23 downto 16)
                    );


            when 12 =>

                result :=
                    std_logic_vector(
                        frequency_value(15 downto 8)
                    );


            when 13 =>

                result :=
                    std_logic_vector(
                        frequency_value(7 downto 0)
                    );



            ----------------------------------------------------------
            -- Active power
            ----------------------------------------------------------

            when 14 =>

                result :=
                    std_logic_vector(
                        active_power_value(31 downto 24)
                    );


            when 15 =>

                result :=
                    std_logic_vector(
                        active_power_value(23 downto 16)
                    );


            when 16 =>

                result :=
                    std_logic_vector(
                        active_power_value(15 downto 8)
                    );


            when 17 =>

                result :=
                    std_logic_vector(
                        active_power_value(7 downto 0)
                    );



            ----------------------------------------------------------
            -- Apparent power
            ----------------------------------------------------------

            when 18 =>

                result :=
                    std_logic_vector(
                        apparent_power_value(31 downto 24)
                    );


            when 19 =>

                result :=
                    std_logic_vector(
                        apparent_power_value(23 downto 16)
                    );


            when 20 =>

                result :=
                    std_logic_vector(
                        apparent_power_value(15 downto 8)
                    );


            when 21 =>

                result :=
                    std_logic_vector(
                        apparent_power_value(7 downto 0)
                    );



            ----------------------------------------------------------
            -- Power factor
            ----------------------------------------------------------

            when 22 =>

                result :=
                    std_logic_vector(
                        power_factor_value(15 downto 8)
                    );


            when 23 =>

                result :=
                    std_logic_vector(
                        power_factor_value(7 downto 0)
                    );



            ----------------------------------------------------------
            -- Voltage THD
            ----------------------------------------------------------

            when 24 =>

                result :=
                    std_logic_vector(
                        voltage_thd_value(15 downto 8)
                    );


            when 25 =>

                result :=
                    std_logic_vector(
                        voltage_thd_value(7 downto 0)
                    );



            ----------------------------------------------------------
            -- Current THD
            ----------------------------------------------------------

            when 26 =>

                result :=
                    std_logic_vector(
                        current_thd_value(15 downto 8)
                    );


            when 27 =>

                result :=
                    std_logic_vector(
                        current_thd_value(7 downto 0)
                    );



            ----------------------------------------------------------
            -- NEW:
            -- Actual THD electrical-cycle sample count
            ----------------------------------------------------------

            when 28 =>

                result :=
                    std_logic_vector(
                        thd_frame_samples_value(15 downto 8)
                    );


            when 29 =>

                result :=
                    std_logic_vector(
                        thd_frame_samples_value(7 downto 0)
                    );



            when others =>

                result :=
                    x"00";


        end case;


        return result;


    end function;



begin


    ------------------------------------------------------------------
    -- Outputs
    ------------------------------------------------------------------

    uart_data <=
        uart_data_reg;


    uart_start <=
        uart_start_reg;


    packet_busy <=
        packet_busy_reg;



    ------------------------------------------------------------------
    -- Packet transmitter state machine
    ------------------------------------------------------------------

    process(clk_100mhz)

    begin


        if rising_edge(clk_100mhz) then


            ----------------------------------------------------------
            -- Default:
            -- uart_start is only a one-clock pulse.
            ----------------------------------------------------------

            uart_start_reg <=
                '0';



            ----------------------------------------------------------
            -- RESET
            ----------------------------------------------------------

            if reset = '1' then


                state <=
                    IDLE;


                byte_index <=
                    0;


                uart_data_reg <=
                    (others => '0');


                uart_start_reg <=
                    '0';


                packet_busy_reg <=
                    '0';



                vrms_reg <=
                    (others => '0');


                irms_reg <=
                    (others => '0');


                frequency_reg <=
                    (others => '0');


                active_power_reg <=
                    (others => '0');


                apparent_power_reg <=
                    (others => '0');


                power_factor_reg <=
                    (others => '0');


                voltage_thd_reg <=
                    (others => '0');


                current_thd_reg <=
                    (others => '0');


                thd_frame_samples_reg <=
                    (others => '0');



            else


                case state is



                    --------------------------------------------------
                    -- Wait for a complete measurement frame
                    --------------------------------------------------

                    when IDLE =>


                        packet_busy_reg <=
                            '0';


                        byte_index <=
                            0;



                        if packet_trigger = '1' then


                            ------------------------------------------------
                            -- Snapshot every metric at the same time.
                            ------------------------------------------------

                            vrms_reg <=
                                voltage_rms_mV;


                            irms_reg <=
                                current_rms_uA;


                            frequency_reg <=
                                frequency_mHz;


                            active_power_reg <=
                                active_power_mW;


                            apparent_power_reg <=
                                apparent_power_mVA;


                            power_factor_reg <=
                                power_factor_milli;


                            voltage_thd_reg <=
                                voltage_thd_x100;


                            current_thd_reg <=
                                current_thd_x100;


                            ------------------------------------------------
                            -- NEW diagnostic snapshot
                            ------------------------------------------------

                            thd_frame_samples_reg <=
                                thd_frame_samples;


                            packet_busy_reg <=
                                '1';


                            state <=
                                SEND_BYTE;


                        end if;



                    --------------------------------------------------
                    -- Send next packet byte to UART
                    --------------------------------------------------

                    when SEND_BYTE =>


                        packet_busy_reg <=
                            '1';



                        if uart_busy = '0' then


                            uart_data_reg <=
                                get_packet_byte(

                                    byte_index,

                                    vrms_reg,

                                    irms_reg,

                                    frequency_reg,

                                    active_power_reg,

                                    apparent_power_reg,

                                    power_factor_reg,

                                    voltage_thd_reg,

                                    current_thd_reg,

                                    thd_frame_samples_reg

                                );


                            uart_start_reg <=
                                '1';


                            state <=
                                WAIT_BUSY;


                        end if;



                    --------------------------------------------------
                    -- Wait until UART accepts byte
                    --------------------------------------------------

                    when WAIT_BUSY =>


                        packet_busy_reg <=
                            '1';



                        if uart_busy = '1' then


                            state <=
                                WAIT_DONE;


                        end if;



                    --------------------------------------------------
                    -- Wait until UART finishes byte
                    --------------------------------------------------

                    when WAIT_DONE =>


                        packet_busy_reg <=
                            '1';



                        if uart_busy = '0' then


                            if
                                byte_index =
                                PACKET_LENGTH - 1
                            then


                                byte_index <=
                                    0;


                                packet_busy_reg <=
                                    '0';


                                state <=
                                    IDLE;


                            else


                                byte_index <=
                                    byte_index + 1;


                                state <=
                                    SEND_BYTE;


                            end if;


                        end if;


                end case;


            end if;


        end if;


    end process;


end architecture rtl;