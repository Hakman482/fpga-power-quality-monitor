library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity pq_uart_packet_tx is

    generic (
        SAMPLE_RATE_HZ       : positive := 10_000;
        SAMPLE_FRAME_SAMPLES : positive := 1_000;
        FRAME_PERIOD_SAMPLES : positive := 10_000
    );

    port (
        clk_100mhz : in std_logic;
        reset      : in std_logic;

        --------------------------------------------------------------
        -- Raw ADC codes and instantaneous scaled V/I samples
        --------------------------------------------------------------

        voltage_raw_in :
            in std_logic_vector(15 downto 0);

        current_raw_in :
            in std_logic_vector(15 downto 0);

        voltage_mV_in :
            in signed(31 downto 0);

        current_uA_in :
            in signed(31 downto 0);

        sample_valid :
            in std_logic;


        --------------------------------------------------------------
        -- FPGA-computed PQ metrics
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

        metric_trigger :
            in std_logic;


        --------------------------------------------------------------
        -- UART byte-level interface
        --------------------------------------------------------------

        uart_busy :
            in std_logic;

        uart_data :
            out std_logic_vector(7 downto 0);

        uart_start :
            out std_logic;


        packet_busy :
            out std_logic
    );

end entity pq_uart_packet_tx;


architecture rtl of pq_uart_packet_tx is


    ------------------------------------------------------------------
    -- Packet lengths
    ------------------------------------------------------------------

    constant METRIC_BYTES :
        positive := 28;


    constant SAMPLE_HEADER_BYTES :
        positive := 11;


    constant SAMPLE_BYTES :
        positive :=
            SAMPLE_HEADER_BYTES +
            SAMPLE_FRAME_SAMPLES * 12;



    ------------------------------------------------------------------
    -- BRAM waveform storage
    --
    -- One 96-bit word contains one complete V/I sample pair:
    --
    -- bits 95 downto 80 = raw voltage ADC code
    -- bits 79 downto 64 = raw current ADC code
    -- bits 63 downto 32 = voltage_mV
    -- bits 31 downto  0 = current_uA
    --
    -- At 1000 samples:
    --
    -- 1000 × 96 = 96,000 bits
    --
    -- This is intentionally structured for block-RAM inference.
    ------------------------------------------------------------------

    type sample_mem_t is array (
        0 to SAMPLE_FRAME_SAMPLES - 1
    ) of std_logic_vector(95 downto 0);


    signal sample_mem :
        sample_mem_t;


    attribute ram_style :
        string;


    attribute ram_style of sample_mem :
        signal is "block";



    ------------------------------------------------------------------
    -- BRAM write interface
    ------------------------------------------------------------------

    signal mem_wr_en :
        std_logic := '0';


    signal mem_wr_addr :
        integer range 0 to SAMPLE_FRAME_SAMPLES - 1 := 0;


    signal mem_wr_data :
        std_logic_vector(95 downto 0) :=
            (others => '0');



    ------------------------------------------------------------------
    -- BRAM synchronous read interface
    ------------------------------------------------------------------

    signal mem_rd_addr :
        integer range 0 to SAMPLE_FRAME_SAMPLES - 1 := 0;


    signal mem_rd_data :
        std_logic_vector(95 downto 0) :=
            (others => '0');



    ------------------------------------------------------------------
    -- Waveform capture controller
    ------------------------------------------------------------------

    signal capture_active :
        std_logic := '0';


    signal capture_index :
        integer range 0 to SAMPLE_FRAME_SAMPLES - 1 := 0;


    signal period_count :
        integer range 0 to FRAME_PERIOD_SAMPLES - 1 := 0;


    signal sample_pending :
        std_logic := '0';


    signal sample_seq :
        unsigned(15 downto 0) :=
            (others => '0');



    ------------------------------------------------------------------
    -- Metric snapshot registers
    ------------------------------------------------------------------

    signal m_vrms :
        unsigned(31 downto 0) :=
            (others => '0');


    signal m_irms :
        unsigned(31 downto 0) :=
            (others => '0');


    signal m_freq :
        unsigned(31 downto 0) :=
            (others => '0');


    signal m_p :
        signed(31 downto 0) :=
            (others => '0');


    signal m_s :
        unsigned(31 downto 0) :=
            (others => '0');


    signal m_pf :
        signed(15 downto 0) :=
            (others => '0');


    signal m_thdv :
        unsigned(15 downto 0) :=
            (others => '0');


    signal m_thdi :
        unsigned(15 downto 0) :=
            (others => '0');


    signal metric_pending :
        std_logic := '0';



    ------------------------------------------------------------------
    -- Metric transmission snapshot
    --
    -- Once AA55 transmission begins, these registers remain stable
    -- even if the DSP produces a newer metric result.
    ------------------------------------------------------------------

    signal tx_vrms :
        unsigned(31 downto 0) :=
            (others => '0');


    signal tx_irms :
        unsigned(31 downto 0) :=
            (others => '0');


    signal tx_freq :
        unsigned(31 downto 0) :=
            (others => '0');


    signal tx_p :
        signed(31 downto 0) :=
            (others => '0');


    signal tx_s :
        unsigned(31 downto 0) :=
            (others => '0');


    signal tx_pf :
        signed(15 downto 0) :=
            (others => '0');


    signal tx_thdv :
        unsigned(15 downto 0) :=
            (others => '0');


    signal tx_thdi :
        unsigned(15 downto 0) :=
            (others => '0');



    ------------------------------------------------------------------
    -- Packet scheduler acknowledgement
    ------------------------------------------------------------------

    signal metric_taken :
        std_logic := '0';


    signal sample_taken :
        std_logic := '0';



    ------------------------------------------------------------------
    -- Packet type
    ------------------------------------------------------------------

    type tx_kind_t is (
        TX_IDLE,
        TX_METRIC,
        TX_SAMPLE
    );


    signal tx_kind :
        tx_kind_t :=
            TX_IDLE;



    ------------------------------------------------------------------
    -- UART packet byte index
    ------------------------------------------------------------------

    signal byte_index :
        integer range 0 to SAMPLE_BYTES - 1 :=
            0;



    ------------------------------------------------------------------
    -- Byte helper functions
    ------------------------------------------------------------------

    function u32_byte(
        x : unsigned(31 downto 0);
        n : integer
    )
        return std_logic_vector
    is

    begin

        case n is

            when 0 =>

                return std_logic_vector(
                    x(31 downto 24)
                );


            when 1 =>

                return std_logic_vector(
                    x(23 downto 16)
                );


            when 2 =>

                return std_logic_vector(
                    x(15 downto 8)
                );


            when others =>

                return std_logic_vector(
                    x(7 downto 0)
                );

        end case;

    end function;



    function s32_byte(
        x : signed(31 downto 0);
        n : integer
    )
        return std_logic_vector
    is

    begin

        return u32_byte(
            unsigned(x),
            n
        );

    end function;



    function u16_byte(
        x : unsigned(15 downto 0);
        n : integer
    )
        return std_logic_vector
    is

    begin

        if n = 0 then

            return std_logic_vector(
                x(15 downto 8)
            );

        else

            return std_logic_vector(
                x(7 downto 0)
            );

        end if;

    end function;



    function s16_byte(
        x : signed(15 downto 0);
        n : integer
    )
        return std_logic_vector
    is

    begin

        return u16_byte(
            unsigned(x),
            n
        );

    end function;



begin


    ------------------------------------------------------------------
    -- Transmitter busy status
    ------------------------------------------------------------------

    packet_busy <=
        '1'
        when tx_kind /= TX_IDLE
        else '0';



    ------------------------------------------------------------------
    -- BLOCK RAM
    --
    -- Simple dual-port style:
    --
    -- write port:
    -- mem_wr_en / mem_wr_addr / mem_wr_data
    --
    -- read port:
    -- mem_rd_addr -> mem_rd_data
    --
    -- The read is synchronous, which is important for BRAM inference.
    ------------------------------------------------------------------

    SAMPLE_BRAM :
    process(clk_100mhz)

    begin

        if rising_edge(clk_100mhz) then


            ----------------------------------------------------------
            -- Write port
            ----------------------------------------------------------

            if mem_wr_en = '1' then

                sample_mem(mem_wr_addr) <=
                    mem_wr_data;

            end if;



            ----------------------------------------------------------
            -- Synchronous read port
            ----------------------------------------------------------

            mem_rd_data <=
                sample_mem(mem_rd_addr);


        end if;

    end process SAMPLE_BRAM;



    ------------------------------------------------------------------
    -- CAPTURE PROCESS
    ------------------------------------------------------------------

    CAPTURE_PROCESS :
    process(clk_100mhz)

    begin

        if rising_edge(clk_100mhz) then


            ----------------------------------------------------------
            -- Write disabled unless explicitly requested below.
            ----------------------------------------------------------

            mem_wr_en <=
                '0';


            if reset = '1' then


                capture_active <=
                    '0';


                capture_index <=
                    0;


                period_count <=
                    0;


                sample_pending <=
                    '0';


                sample_seq <=
                    (others => '0');


                metric_pending <=
                    '0';


                mem_wr_addr <=
                    0;


                mem_wr_data <=
                    (others => '0');


            else


                ------------------------------------------------------
                -- Scheduler has accepted previous metric packet.
                ------------------------------------------------------

                if metric_taken = '1' then

                    metric_pending <=
                        '0';

                end if;



                ------------------------------------------------------
                -- Scheduler has accepted previous sample frame.
                ------------------------------------------------------

                if sample_taken = '1' then

                    sample_pending <=
                        '0';

                end if;



                ------------------------------------------------------
                -- Store a newly completed metric set.
                --
                -- This is intentionally after metric_taken so that
                -- a new DSP result on the same clock is not lost.
                ------------------------------------------------------

                if metric_trigger = '1' then


                    m_vrms <=
                        voltage_rms_mV;


                    m_irms <=
                        current_rms_uA;


                    m_freq <=
                        frequency_mHz;


                    m_p <=
                        active_power_mW;


                    m_s <=
                        apparent_power_mVA;


                    m_pf <=
                        power_factor_milli;


                    m_thdv <=
                        voltage_thd_x100;


                    m_thdi <=
                        current_thd_x100;


                    metric_pending <=
                        '1';


                end if;



                ------------------------------------------------------
                -- Process incoming V/I samples.
                ------------------------------------------------------

                if sample_valid = '1' then


                    --------------------------------------------------
                    -- Capture is currently active.
                    --------------------------------------------------

                    if capture_active = '1' then


                        mem_wr_en <=
                            '1';


                        mem_wr_addr <=
                            capture_index;


                        mem_wr_data <=
                            voltage_raw_in &
                            current_raw_in &
                            std_logic_vector(
                                voltage_mV_in
                            ) &
                            std_logic_vector(
                                current_uA_in
                            );



                        --------------------------------------------------
                        -- Last sample of reference frame.
                        --------------------------------------------------

                        if
                            capture_index =
                            SAMPLE_FRAME_SAMPLES - 1
                        then


                            capture_active <=
                                '0';


                            capture_index <=
                                0;


                            sample_pending <=
                                '1';


                            sample_seq <=
                                sample_seq + 1;


                        else


                            capture_index <=
                                capture_index + 1;


                        end if;



                    --------------------------------------------------
                    -- No active capture.
                    --------------------------------------------------

                    elsif sample_pending = '0' then


                        --------------------------------------------------
                        -- Start another reference capture.
                        --------------------------------------------------

                        if
                            period_count =
                            FRAME_PERIOD_SAMPLES - 1
                        then


                            period_count <=
                                0;


                            --------------------------------------------------
                            -- Store first pair immediately.
                            --------------------------------------------------

                            mem_wr_en <=
                                '1';


                            mem_wr_addr <=
                                0;


                            mem_wr_data <=
                                voltage_raw_in &
                                current_raw_in &
                                std_logic_vector(
                                    voltage_mV_in
                                ) &
                                std_logic_vector(
                                    current_uA_in
                                );


                            if SAMPLE_FRAME_SAMPLES = 1 then


                                sample_pending <=
                                    '1';


                                sample_seq <=
                                    sample_seq + 1;


                            else


                                capture_active <=
                                    '1';


                                capture_index <=
                                    1;


                            end if;


                        else


                            period_count <=
                                period_count + 1;


                        end if;


                    end if;


                end if;


            end if;


        end if;

    end process CAPTURE_PROCESS;



    ------------------------------------------------------------------
    -- PACKET TRANSMITTER
    ------------------------------------------------------------------

    TX_PROCESS :
    process(clk_100mhz)


        type byte_phase_t is (

            BYTE_READY,

            WAIT_BUSY_HIGH,

            WAIT_BUSY_LOW,

            RAM_READ_WAIT

        );


        variable byte_phase :
            byte_phase_t :=
                BYTE_READY;


        variable d :
            std_logic_vector(7 downto 0);


        variable payload_index :
            integer;


        variable sample_index :
            integer;


        variable sample_byte :
            integer;


        variable count_u16 :
            unsigned(15 downto 0);


        variable fs_u32 :
            unsigned(31 downto 0);


    begin


        if rising_edge(clk_100mhz) then


            ----------------------------------------------------------
            -- One-clock default pulses
            ----------------------------------------------------------

            uart_start <=
                '0';


            metric_taken <=
                '0';


            sample_taken <=
                '0';



            if reset = '1' then


                tx_kind <=
                    TX_IDLE;


                byte_index <=
                    0;


                uart_data <=
                    (others => '0');


                mem_rd_addr <=
                    0;


                byte_phase :=
                    BYTE_READY;


            else


                ------------------------------------------------------
                -- Choose next packet.
                --
                -- Metrics have priority whenever the transmitter is
                -- completely idle.
                ------------------------------------------------------

                if tx_kind = TX_IDLE then


                    byte_index <=
                        0;


                    byte_phase :=
                        BYTE_READY;



                    if metric_pending = '1' then


                        --------------------------------------------------
                        -- Freeze metric values for this packet.
                        --------------------------------------------------

                        tx_vrms <=
                            m_vrms;


                        tx_irms <=
                            m_irms;


                        tx_freq <=
                            m_freq;


                        tx_p <=
                            m_p;


                        tx_s <=
                            m_s;


                        tx_pf <=
                            m_pf;


                        tx_thdv <=
                            m_thdv;


                        tx_thdi <=
                            m_thdi;


                        metric_taken <=
                            '1';


                        tx_kind <=
                            TX_METRIC;



                    elsif sample_pending = '1' then


                        --------------------------------------------------
                        -- Begin AA56 packet.
                        --
                        -- Address zero is presented to BRAM well before
                        -- the first payload byte is required, since the
                        -- eleven header bytes transmit first.
                        --------------------------------------------------

                        mem_rd_addr <=
                            0;


                        sample_taken <=
                            '1';


                        tx_kind <=
                            TX_SAMPLE;


                    end if;



                ------------------------------------------------------
                -- RAM wait cycle.
                --
                -- Because BRAM output is synchronous, after changing
                -- mem_rd_addr we wait one complete controller cycle
                -- before transmitting bytes from the new sample word.
                ------------------------------------------------------

                elsif byte_phase = RAM_READ_WAIT then


                    byte_phase :=
                        BYTE_READY;



                ------------------------------------------------------
                -- Build and submit next byte.
                ------------------------------------------------------

                elsif byte_phase = BYTE_READY then


                    if uart_busy = '0' then


                        d :=
                            (others => '0');



                        --------------------------------------------------
                        -- AA55 METRIC PACKET
                        --------------------------------------------------

                        if tx_kind = TX_METRIC then


                            case byte_index is


                                when 0 =>

                                    d := x"AA";


                                when 1 =>

                                    d := x"55";



                                --------------------------------------------------
                                -- Vrms
                                --------------------------------------------------

                                when 2 =>

                                    d := u32_byte(
                                        tx_vrms,
                                        0
                                    );


                                when 3 =>

                                    d := u32_byte(
                                        tx_vrms,
                                        1
                                    );


                                when 4 =>

                                    d := u32_byte(
                                        tx_vrms,
                                        2
                                    );


                                when 5 =>

                                    d := u32_byte(
                                        tx_vrms,
                                        3
                                    );



                                --------------------------------------------------
                                -- Irms
                                --------------------------------------------------

                                when 6 =>

                                    d := u32_byte(
                                        tx_irms,
                                        0
                                    );


                                when 7 =>

                                    d := u32_byte(
                                        tx_irms,
                                        1
                                    );


                                when 8 =>

                                    d := u32_byte(
                                        tx_irms,
                                        2
                                    );


                                when 9 =>

                                    d := u32_byte(
                                        tx_irms,
                                        3
                                    );



                                --------------------------------------------------
                                -- Frequency
                                --------------------------------------------------

                                when 10 =>

                                    d := u32_byte(
                                        tx_freq,
                                        0
                                    );


                                when 11 =>

                                    d := u32_byte(
                                        tx_freq,
                                        1
                                    );


                                when 12 =>

                                    d := u32_byte(
                                        tx_freq,
                                        2
                                    );


                                when 13 =>

                                    d := u32_byte(
                                        tx_freq,
                                        3
                                    );



                                --------------------------------------------------
                                -- Active power
                                --------------------------------------------------

                                when 14 =>

                                    d := s32_byte(
                                        tx_p,
                                        0
                                    );


                                when 15 =>

                                    d := s32_byte(
                                        tx_p,
                                        1
                                    );


                                when 16 =>

                                    d := s32_byte(
                                        tx_p,
                                        2
                                    );


                                when 17 =>

                                    d := s32_byte(
                                        tx_p,
                                        3
                                    );



                                --------------------------------------------------
                                -- Apparent power
                                --------------------------------------------------

                                when 18 =>

                                    d := u32_byte(
                                        tx_s,
                                        0
                                    );


                                when 19 =>

                                    d := u32_byte(
                                        tx_s,
                                        1
                                    );


                                when 20 =>

                                    d := u32_byte(
                                        tx_s,
                                        2
                                    );


                                when 21 =>

                                    d := u32_byte(
                                        tx_s,
                                        3
                                    );



                                --------------------------------------------------
                                -- Power factor
                                --------------------------------------------------

                                when 22 =>

                                    d := s16_byte(
                                        tx_pf,
                                        0
                                    );


                                when 23 =>

                                    d := s16_byte(
                                        tx_pf,
                                        1
                                    );



                                --------------------------------------------------
                                -- THD-V
                                --------------------------------------------------

                                when 24 =>

                                    d := u16_byte(
                                        tx_thdv,
                                        0
                                    );


                                when 25 =>

                                    d := u16_byte(
                                        tx_thdv,
                                        1
                                    );



                                --------------------------------------------------
                                -- THD-I
                                --------------------------------------------------

                                when 26 =>

                                    d := u16_byte(
                                        tx_thdi,
                                        0
                                    );


                                when 27 =>

                                    d := u16_byte(
                                        tx_thdi,
                                        1
                                    );


                                when others =>

                                    d :=
                                        x"00";


                            end case;



                        --------------------------------------------------
                        -- AA56 SAMPLE FRAME
                        --------------------------------------------------

                        else


                            count_u16 :=
                                to_unsigned(
                                    SAMPLE_FRAME_SAMPLES,
                                    16
                                );


                            fs_u32 :=
                                to_unsigned(
                                    SAMPLE_RATE_HZ,
                                    32
                                );



                            --------------------------------------------------
                            -- Packet header
                            --------------------------------------------------

                            if byte_index = 0 then


                                d :=
                                    x"AA";


                            elsif byte_index = 1 then


                                d :=
                                    x"56";


                            --------------------------------------------------
                            -- Protocol version
                            --------------------------------------------------

                            elsif byte_index = 2 then


                                d :=
                                    x"02";


                            --------------------------------------------------
                            -- Sample count
                            --------------------------------------------------

                            elsif byte_index = 3 then


                                d :=
                                    u16_byte(
                                        count_u16,
                                        0
                                    );


                            elsif byte_index = 4 then


                                d :=
                                    u16_byte(
                                        count_u16,
                                        1
                                    );


                            --------------------------------------------------
                            -- Sampling frequency
                            --------------------------------------------------

                            elsif
                                byte_index >= 5 and
                                byte_index <= 8
                            then


                                d :=
                                    u32_byte(
                                        fs_u32,
                                        byte_index - 5
                                    );


                            --------------------------------------------------
                            -- Frame sequence
                            --------------------------------------------------

                            elsif byte_index = 9 then


                                d :=
                                    u16_byte(
                                        sample_seq,
                                        0
                                    );


                            elsif byte_index = 10 then


                                d :=
                                    u16_byte(
                                        sample_seq,
                                        1
                                    );


                            --------------------------------------------------
                            -- BRAM sample payload
                            --------------------------------------------------

                            else


                                payload_index :=
                                    byte_index -
                                    SAMPLE_HEADER_BYTES;


                                sample_index :=
                                    payload_index / 12;


                                sample_byte :=
                                    payload_index mod 12;



                                --------------------------------------------------
                                -- Packed BRAM word:
                                --
                                -- 95:80 = raw voltage code
                                -- 79:64 = raw current code
                                -- 63:32 = scaled voltage
                                -- 31:0  = scaled current
                                --------------------------------------------------

                                case sample_byte is


                                    when 0 =>

                                        d :=
                                            mem_rd_data(
                                                95 downto 88
                                            );


                                    when 1 =>

                                        d :=
                                            mem_rd_data(
                                                87 downto 80
                                            );


                                    when 2 =>

                                        d :=
                                            mem_rd_data(
                                                79 downto 72
                                            );


                                    when 3 =>

                                        d :=
                                            mem_rd_data(
                                                71 downto 64
                                            );


                                    when 4 =>

                                        d :=
                                            mem_rd_data(
                                                63 downto 56
                                            );


                                    when 5 =>

                                        d :=
                                            mem_rd_data(
                                                55 downto 48
                                            );


                                    when 6 =>

                                        d :=
                                            mem_rd_data(
                                                47 downto 40
                                            );


                                    when 7 =>

                                        d :=
                                            mem_rd_data(
                                                39 downto 32
                                            );


                                    when 8 =>

                                        d :=
                                            mem_rd_data(
                                                31 downto 24
                                            );


                                    when 9 =>

                                        d :=
                                            mem_rd_data(
                                                23 downto 16
                                            );


                                    when 10 =>

                                        d :=
                                            mem_rd_data(
                                                15 downto 8
                                            );


                                    when others =>

                                        d :=
                                            mem_rd_data(
                                                7 downto 0
                                            );


                                end case;


                            end if;


                        end if;



                        --------------------------------------------------
                        -- Submit byte to UART.
                        --------------------------------------------------

                        uart_data <=
                            d;


                        uart_start <=
                            '1';


                        byte_phase :=
                            WAIT_BUSY_HIGH;


                    end if;



                ------------------------------------------------------
                -- Wait for uart_tx to accept byte.
                ------------------------------------------------------

                elsif byte_phase = WAIT_BUSY_HIGH then


                    if uart_busy = '1' then


                        byte_phase :=
                            WAIT_BUSY_LOW;


                    end if;



                ------------------------------------------------------
                -- Wait for complete UART byte.
                ------------------------------------------------------

                else


                    if uart_busy = '0' then



                        --------------------------------------------------
                        -- AA55 packet
                        --------------------------------------------------

                        if tx_kind = TX_METRIC then


                            if
                                byte_index =
                                METRIC_BYTES - 1
                            then


                                tx_kind <=
                                    TX_IDLE;


                                byte_index <=
                                    0;


                                byte_phase :=
                                    BYTE_READY;


                            else


                                byte_index <=
                                    byte_index + 1;


                                byte_phase :=
                                    BYTE_READY;


                            end if;



                        --------------------------------------------------
                        -- AA56 packet
                        --------------------------------------------------

                        else


                            if
                                byte_index =
                                SAMPLE_BYTES - 1
                            then


                                tx_kind <=
                                    TX_IDLE;


                                byte_index <=
                                    0;


                                byte_phase :=
                                    BYTE_READY;


                            else


                                --------------------------------------------------
                                -- Have we just completed the twelfth byte
                                -- of one V/I pair?
                                --
                                -- If so, point BRAM to the next sample
                                -- and allow synchronous read latency.
                                --------------------------------------------------

                                if
                                    byte_index >=
                                    SAMPLE_HEADER_BYTES
                                then


                                    payload_index :=
                                        byte_index -
                                        SAMPLE_HEADER_BYTES;


                                    sample_byte :=
                                        payload_index mod 12;


                                    sample_index :=
                                        payload_index / 12;


                                    if sample_byte = 11 then


                                        if
                                            sample_index <
                                            SAMPLE_FRAME_SAMPLES - 1
                                        then


                                            mem_rd_addr <=
                                                sample_index + 1;


                                            byte_index <=
                                                byte_index + 1;


                                            byte_phase :=
                                                RAM_READ_WAIT;


                                        else


                                            byte_index <=
                                                byte_index + 1;


                                            byte_phase :=
                                                BYTE_READY;


                                        end if;


                                    else


                                        byte_index <=
                                            byte_index + 1;


                                        byte_phase :=
                                            BYTE_READY;


                                    end if;


                                else


                                    byte_index <=
                                        byte_index + 1;


                                    byte_phase :=
                                        BYTE_READY;


                                end if;


                            end if;


                        end if;


                    end if;


                end if;


            end if;


        end if;


    end process TX_PROCESS;


end architecture rtl;
