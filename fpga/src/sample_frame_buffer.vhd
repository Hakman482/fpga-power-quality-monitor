library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library xpm;
use xpm.vcomponents.all;


entity sample_frame_buffer is

    generic (

        --------------------------------------------------------------
        -- Maximum electrical-cycle length.
        --
        -- Current acquisition_pipeline uses 210.
        --------------------------------------------------------------
        FRAME_SAMPLES :
            positive := 210

    );

    port (

        --------------------------------------------------------------
        -- FPGA system
        --------------------------------------------------------------
        clk_100mhz :
            in std_logic;

        reset :
            in std_logic;


        --------------------------------------------------------------
        -- Scaled input samples
        --------------------------------------------------------------
        voltage_mV_in :
            in signed(31 downto 0);

        current_uA_in :
            in signed(31 downto 0);

        sample_valid_in :
            in std_logic;


        --------------------------------------------------------------
        -- New completed electrical-cycle frame
        --------------------------------------------------------------
        frame_valid :
            out std_logic;


        --------------------------------------------------------------
        -- Actual samples in completed electrical cycle
        --------------------------------------------------------------
        sample_count_out :
            out unsigned(15 downto 0);


        --------------------------------------------------------------
        -- Harmonic-engine read interface
        --------------------------------------------------------------
        read_index :
            in unsigned(15 downto 0);

        voltage_mV_out :
            out signed(31 downto 0);

        current_uA_out :
            out signed(31 downto 0)

    );

end entity sample_frame_buffer;



architecture rtl of sample_frame_buffer is


    ------------------------------------------------------------------
    -- Accepted cycle range
    --
    -- At 10 kS/s:
    --
    -- 190 samples ≈ 52.63 Hz
    -- 210 samples ≈ 47.62 Hz
    ------------------------------------------------------------------

    constant MIN_CYCLE_SAMPLES :
        integer := 190;



    ------------------------------------------------------------------
    -- Memory format
    --
    -- One 64-bit word stores both channels:
    --
    -- bits 63 downto 32 = voltage_mV
    -- bits 31 downto 0  = current_uA
    ------------------------------------------------------------------

    constant DATA_WIDTH :
        positive := 64;


    ------------------------------------------------------------------
    -- 210 locations require 8 address bits.
    --
    -- 2^8 = 256
    ------------------------------------------------------------------

    constant ADDR_WIDTH :
        positive := 8;


    ------------------------------------------------------------------
    -- Actual requested XPM memory capacity in bits.
    ------------------------------------------------------------------

    constant MEMORY_SIZE_BITS :
        positive :=
        FRAME_SAMPLES * DATA_WIDTH;



    ------------------------------------------------------------------
    -- Capture-bank control
    --
    -- write_bank:
    --
    --   '0' -> capture into BRAM bank 0
    --   '1' -> capture into BRAM bank 1
    --
    -- frozen_read_bank identifies the completed frame currently
    -- available to the harmonic processor.
    ------------------------------------------------------------------

    signal write_bank :
        std_logic := '0';


    signal frozen_read_bank :
        std_logic := '1';



    ------------------------------------------------------------------
    -- Capture state
    ------------------------------------------------------------------

    signal previous_voltage :
        signed(31 downto 0) :=
        (others => '0');


    signal capture_started :
        std_logic := '0';


    signal write_count :
        integer range 0 to FRAME_SAMPLES :=
        0;


    signal frame_count_reg :
        unsigned(15 downto 0) :=
        (others => '0');



    ------------------------------------------------------------------
    -- Packed write data
    ------------------------------------------------------------------

    signal write_data :
        std_logic_vector(63 downto 0) :=
        (others => '0');



    ------------------------------------------------------------------
    -- XPM write addresses
    ------------------------------------------------------------------

    signal write_addr_bank_0 :
        std_logic_vector(
            ADDR_WIDTH - 1 downto 0
        ) :=
        (others => '0');


    signal write_addr_bank_1 :
        std_logic_vector(
            ADDR_WIDTH - 1 downto 0
        ) :=
        (others => '0');



    ------------------------------------------------------------------
    -- Write enables
    ------------------------------------------------------------------

    signal write_enable_bank_0 :
        std_logic_vector(0 downto 0) :=
        (others => '0');


    signal write_enable_bank_1 :
        std_logic_vector(0 downto 0) :=
        (others => '0');


    signal enable_bank_0 :
        std_logic := '0';


    signal enable_bank_1 :
        std_logic := '0';



    ------------------------------------------------------------------
    -- Common read address
    ------------------------------------------------------------------

    signal read_addr :
        std_logic_vector(
            ADDR_WIDTH - 1 downto 0
        ) :=
        (others => '0');



    ------------------------------------------------------------------
    -- XPM read outputs
    ------------------------------------------------------------------

    signal read_data_bank_0 :
        std_logic_vector(63 downto 0) :=
        (others => '0');


    signal read_data_bank_1 :
        std_logic_vector(63 downto 0) :=
        (others => '0');



    ------------------------------------------------------------------
    -- Selected frozen-frame output
    ------------------------------------------------------------------

    signal selected_read_data :
        std_logic_vector(63 downto 0) :=
        (others => '0');



    ------------------------------------------------------------------
    -- ECC status outputs.
    --
    -- ECC is disabled, but XPM still exposes these ports.
    ------------------------------------------------------------------

    signal bank0_sbiterr :
        std_logic;

    signal bank0_dbiterr :
        std_logic;

    signal bank1_sbiterr :
        std_logic;

    signal bank1_dbiterr :
        std_logic;



begin


    ------------------------------------------------------------------
    -- External frame length
    ------------------------------------------------------------------

    sample_count_out <=
        frame_count_reg;



    ------------------------------------------------------------------
    -- Convert harmonic read index into XPM address.
    --
    -- Only the low 8 bits are needed because valid addresses are
    -- 0 ... 209.
    ------------------------------------------------------------------

    read_addr <=
        std_logic_vector(
            read_index(
                ADDR_WIDTH - 1 downto 0
            )
        );



    ------------------------------------------------------------------
    -- Select frozen bank AFTER the BRAM output registers.
    --
    -- This is only one 64-bit 2:1 mux, rather than distributed RAM
    -- spread throughout the FPGA.
    ------------------------------------------------------------------

    selected_read_data <=
        read_data_bank_0
        when frozen_read_bank = '0'
        else
        read_data_bank_1;



    ------------------------------------------------------------------
    -- Split packed word back into V and I.
    ------------------------------------------------------------------

    voltage_mV_out <=
        signed(
            selected_read_data(
                63 downto 32
            )
        );


    current_uA_out <=
        signed(
            selected_read_data(
                31 downto 0
            )
        );



    ------------------------------------------------------------------
    -- XPM BLOCK RAM BANK 0
    ------------------------------------------------------------------

    FRAME_BRAM_BANK_0 :
        xpm_memory_sdpram

        generic map (

            ADDR_WIDTH_A =>
                ADDR_WIDTH,

            ADDR_WIDTH_B =>
                ADDR_WIDTH,


            AUTO_SLEEP_TIME =>
                0,


            BYTE_WRITE_WIDTH_A =>
                DATA_WIDTH,


            CLOCKING_MODE =>
                "common_clock",


            ECC_MODE =>
                "no_ecc",


            MEMORY_INIT_FILE =>
                "none",

            MEMORY_INIT_PARAM =>
                "0",


            MEMORY_OPTIMIZATION =>
                "true",


            ----------------------------------------------------------
            -- IMPORTANT:
            -- Explicitly force Block RAM.
            ----------------------------------------------------------

            MEMORY_PRIMITIVE =>
                "block",


            MEMORY_SIZE =>
                MEMORY_SIZE_BITS,


            MESSAGE_CONTROL =>
                0,


            READ_DATA_WIDTH_B =>
                DATA_WIDTH,


            ----------------------------------------------------------
            -- One BRAM output clock of read latency.
            --
            -- harmonic_1_25_extractor already has:
            --
            -- REQUEST_SAMPLE
            -- WAIT_SAMPLE
            -- PROCESS_SAMPLE
            ----------------------------------------------------------

            READ_LATENCY_B =>
                1,


            READ_RESET_VALUE_B =>
                "0",


            RST_MODE_A =>
                "SYNC",

            RST_MODE_B =>
                "SYNC",


            USE_EMBEDDED_CONSTRAINT =>
                0,


            USE_MEM_INIT =>
                0,


            WAKEUP_TIME =>
                "disable_sleep",


            WRITE_DATA_WIDTH_A =>
                DATA_WIDTH,


            WRITE_MODE_B =>
                "no_change"

        )

        port map (

            ----------------------------------------------------------
            -- Error outputs
            ----------------------------------------------------------

            dbiterrb =>
                bank0_dbiterr,

            sbiterrb =>
                bank0_sbiterr,


            ----------------------------------------------------------
            -- Read output
            ----------------------------------------------------------

            doutb =>
                read_data_bank_0,


            ----------------------------------------------------------
            -- Write address
            ----------------------------------------------------------

            addra =>
                write_addr_bank_0,


            ----------------------------------------------------------
            -- Read address
            ----------------------------------------------------------

            addrb =>
                read_addr,


            ----------------------------------------------------------
            -- Common system clock
            ----------------------------------------------------------

            clka =>
                clk_100mhz,

            clkb =>
                clk_100mhz,


            ----------------------------------------------------------
            -- Write input
            ----------------------------------------------------------

            dina =>
                write_data,


            ----------------------------------------------------------
            -- Port enables
            ----------------------------------------------------------

            ena =>
                enable_bank_0,

            enb =>
                '1',


            ----------------------------------------------------------
            -- ECC injection disabled
            ----------------------------------------------------------

            injectdbiterra =>
                '0',

            injectsbiterra =>
                '0',


            ----------------------------------------------------------
            -- Output register enable
            ----------------------------------------------------------

            regceb =>
                '1',


            ----------------------------------------------------------
            -- Read output reset
            ----------------------------------------------------------

            rstb =>
                reset,


            ----------------------------------------------------------
            -- Dynamic sleep disabled
            ----------------------------------------------------------

            sleep =>
                '0',


            ----------------------------------------------------------
            -- Word-wide write enable
            ----------------------------------------------------------

            wea =>
                write_enable_bank_0

        );



    ------------------------------------------------------------------
    -- XPM BLOCK RAM BANK 1
    ------------------------------------------------------------------

    FRAME_BRAM_BANK_1 :
        xpm_memory_sdpram

        generic map (

            ADDR_WIDTH_A =>
                ADDR_WIDTH,

            ADDR_WIDTH_B =>
                ADDR_WIDTH,


            AUTO_SLEEP_TIME =>
                0,


            BYTE_WRITE_WIDTH_A =>
                DATA_WIDTH,


            CLOCKING_MODE =>
                "common_clock",


            ECC_MODE =>
                "no_ecc",


            MEMORY_INIT_FILE =>
                "none",

            MEMORY_INIT_PARAM =>
                "0",


            MEMORY_OPTIMIZATION =>
                "true",


            ----------------------------------------------------------
            -- Explicit Block RAM
            ----------------------------------------------------------

            MEMORY_PRIMITIVE =>
                "block",


            MEMORY_SIZE =>
                MEMORY_SIZE_BITS,


            MESSAGE_CONTROL =>
                0,


            READ_DATA_WIDTH_B =>
                DATA_WIDTH,


            READ_LATENCY_B =>
                1,


            READ_RESET_VALUE_B =>
                "0",


            RST_MODE_A =>
                "SYNC",

            RST_MODE_B =>
                "SYNC",


            USE_EMBEDDED_CONSTRAINT =>
                0,


            USE_MEM_INIT =>
                0,


            WAKEUP_TIME =>
                "disable_sleep",


            WRITE_DATA_WIDTH_A =>
                DATA_WIDTH,


            WRITE_MODE_B =>
                "no_change"

        )

        port map (

            dbiterrb =>
                bank1_dbiterr,

            doutb =>
                read_data_bank_1,

            sbiterrb =>
                bank1_sbiterr,


            addra =>
                write_addr_bank_1,

            addrb =>
                read_addr,


            clka =>
                clk_100mhz,

            clkb =>
                clk_100mhz,


            dina =>
                write_data,


            ena =>
                enable_bank_1,

            enb =>
                '1',


            injectdbiterra =>
                '0',

            injectsbiterra =>
                '0',


            regceb =>
                '1',


            rstb =>
                reset,


            sleep =>
                '0',


            wea =>
                write_enable_bank_1

        );



    ------------------------------------------------------------------
    -- CYCLE CAPTURE CONTROL
    ------------------------------------------------------------------

    CAPTURE_PROC :
    process(clk_100mhz)


        variable positive_crossing :
            boolean;


        variable packed_sample :
            std_logic_vector(63 downto 0);


    begin


        if rising_edge(clk_100mhz) then


            ----------------------------------------------------------
            -- RESET
            ----------------------------------------------------------

            if reset = '1' then


                write_bank <=
                    '0';


                frozen_read_bank <=
                    '1';


                previous_voltage <=
                    (others => '0');


                capture_started <=
                    '0';


                write_count <=
                    0;


                frame_count_reg <=
                    (others => '0');


                frame_valid <=
                    '0';


                write_data <=
                    (others => '0');


                write_addr_bank_0 <=
                    (others => '0');


                write_addr_bank_1 <=
                    (others => '0');


                enable_bank_0 <=
                    '0';


                enable_bank_1 <=
                    '0';


                write_enable_bank_0 <=
                    (others => '0');


                write_enable_bank_1 <=
                    (others => '0');



            else


                ------------------------------------------------------
                -- Default states
                ------------------------------------------------------

                frame_valid <=
                    '0';


                enable_bank_0 <=
                    '0';


                enable_bank_1 <=
                    '0';


                write_enable_bank_0 <=
                    (others => '0');


                write_enable_bank_1 <=
                    (others => '0');



                ------------------------------------------------------
                -- New scaled sample
                ------------------------------------------------------

                if sample_valid_in = '1' then


                    --------------------------------------------------
                    -- Pack voltage and current
                    --------------------------------------------------

                    packed_sample :=

                        std_logic_vector(
                            voltage_mV_in
                        )

                        &

                        std_logic_vector(
                            current_uA_in
                        );


                    write_data <=
                        packed_sample;



                    --------------------------------------------------
                    -- Detect positive-going voltage crossing
                    --------------------------------------------------

                    positive_crossing :=
                        (
                            previous_voltage < 0
                            and
                            voltage_mV_in >= 0
                        );



                    --------------------------------------------------
                    -- FIRST CROSSING
                    --
                    -- Begin first cycle capture.
                    --------------------------------------------------

                    if
                        capture_started = '0'
                        and
                        positive_crossing
                    then


                        capture_started <=
                            '1';


                        write_count <=
                            1;



                        if write_bank = '0' then


                            write_addr_bank_0 <=
                                std_logic_vector(
                                    to_unsigned(
                                        0,
                                        ADDR_WIDTH
                                    )
                                );


                            enable_bank_0 <=
                                '1';


                            write_enable_bank_0(0) <=
                                '1';


                        else


                            write_addr_bank_1 <=
                                std_logic_vector(
                                    to_unsigned(
                                        0,
                                        ADDR_WIDTH
                                    )
                                );


                            enable_bank_1 <=
                                '1';


                            write_enable_bank_1(0) <=
                                '1';


                        end if;



                    --------------------------------------------------
                    -- NEXT CROSSING
                    --
                    -- Freeze the completed cycle and switch banks.
                    --------------------------------------------------

                    elsif
                        capture_started = '1'
                        and
                        positive_crossing
                    then


                        ------------------------------------------------
                        -- Publish the completed cycle only when its
                        -- length lies in the intended range.
                        ------------------------------------------------

                        if
                            write_count >=
                                MIN_CYCLE_SAMPLES
                            and
                            write_count <=
                                FRAME_SAMPLES
                        then


                            frozen_read_bank <=
                                write_bank;


                            frame_count_reg <=
                                to_unsigned(
                                    write_count,
                                    frame_count_reg'length
                                );


                            frame_valid <=
                                '1';


                        end if;



                        ------------------------------------------------
                        -- Switch write bank.
                        --
                        -- The current crossing sample becomes address
                        -- zero of the next cycle.
                        ------------------------------------------------

                        if write_bank = '0' then


                            write_bank <=
                                '1';


                            write_addr_bank_1 <=
                                std_logic_vector(
                                    to_unsigned(
                                        0,
                                        ADDR_WIDTH
                                    )
                                );


                            enable_bank_1 <=
                                '1';


                            write_enable_bank_1(0) <=
                                '1';


                        else


                            write_bank <=
                                '0';


                            write_addr_bank_0 <=
                                std_logic_vector(
                                    to_unsigned(
                                        0,
                                        ADDR_WIDTH
                                    )
                                );


                            enable_bank_0 <=
                                '1';


                            write_enable_bank_0(0) <=
                                '1';


                        end if;


                        write_count <=
                            1;



                    --------------------------------------------------
                    -- ORDINARY CYCLE SAMPLE
                    --------------------------------------------------

                    elsif capture_started = '1' then


                        if write_count < FRAME_SAMPLES then


                            if write_bank = '0' then


                                write_addr_bank_0 <=
                                    std_logic_vector(
                                        to_unsigned(
                                            write_count,
                                            ADDR_WIDTH
                                        )
                                    );


                                enable_bank_0 <=
                                    '1';


                                write_enable_bank_0(0) <=
                                    '1';


                            else


                                write_addr_bank_1 <=
                                    std_logic_vector(
                                        to_unsigned(
                                            write_count,
                                            ADDR_WIDTH
                                        )
                                    );


                                enable_bank_1 <=
                                    '1';


                                write_enable_bank_1(0) <=
                                    '1';


                            end if;


                            write_count <=
                                write_count + 1;


                        end if;


                    end if;



                    previous_voltage <=
                        voltage_mV_in;


                end if;


            end if;


        end if;


    end process;


end architecture rtl;