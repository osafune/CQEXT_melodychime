-- ===================================================================
-- TITLE : CQ-EXT Melody Chime sample
--
--     DESIGN : S.OSAFUNE (J-7SYSTEM Works)
--     DATE   : 2012/08/17 -> 2012/08/28
--            : 2012/08/28 (FIXED)
--
--     UPDATE : 2015/03/14
-- ===================================================================
-- *******************************************************************
--   Copyright (C) 2012,2015 J-7SYSTEM Works.  All rights Reserved.
--
-- * This module is a free sourcecode and there is NO WARRANTY.
-- * No restriction on use. You can use, modify and redistribute it
--   for personal, non-profit or commercial products UNDER YOUR
--   RESPONSIBILITY.
-- * Redistributions of source code must retain the above copyright
--   notice.
-- *******************************************************************


library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_arith.all;
use IEEE.std_logic_unsigned.all;

entity melodychime_top is
	generic(
		CLOCK_EDGE		: std_logic := '1';		-- Rise edge drive clock
		RESET_LEVEL		: std_logic := '0'		-- Positive logic reset
	);
	port(
		reset			: in  std_logic;		-- async reset
		clk				: in  std_logic;		-- system clock

		test_score_led	: out std_logic_vector(3 downto 0);

		start			: in  std_logic;		-- play start('1':start)

		timing_1ms_out	: out std_logic;		-- 1ms timig pulse out
		tempo_led		: out std_logic;
		aud_l_out		: out std_logic;		-- 1bitDSM-DAC
		aud_r_out		: out std_logic			-- 1bitDSM-DAC
	);
end melodychime_top;

architecture RTL of melodychime_top is
	constant SYSTEMCLOCK_FREQ	: integer := 50000000;		-- 50MHz(DE0)
	constant CLOCKDIV_NUM		: integer := SYSTEMCLOCK_FREQ/100000;
	signal count10us		: integer range 0 to CLOCKDIV_NUM-1;
	signal count1ms			: integer range 0 to 99;
	signal timing_10us_reg	: std_logic;
	signal timing_1ms_reg	: std_logic;
	signal tempo_led_reg	: std_logic;

	signal start_in_reg		: std_logic_vector(2 downto 0);
	signal start_sig		: std_logic;


	component melodychime_seq
	generic(
		CLOCK_EDGE		: std_logic;
		RESET_LEVEL		: std_logic;
		TEMPO_TC		: integer				-- テンポカウンタ(375ms/Tempo=84) 
	);
	port(
		reset			: in  std_logic;
		clk				: in  std_logic;
		timing_1ms		: in  std_logic;
		tempo_out		: out std_logic;

		test_score_addr	: out std_logic_vector(3 downto 0);

		start			: in  std_logic;

		slot_div		: out std_logic_vector(7 downto 0);
		slot_note		: out std_logic;
		slot0_wrreq		: out std_logic;
		slot1_wrreq		: out std_logic	
	);
	end component;
	signal tempo_sig		: std_logic;
	signal slot_div_sig		: std_logic_vector(7 downto 0);
	signal slot_note_sig	: std_logic;
	signal slot0_wrreq_sig	: std_logic;
	signal slot1_wrreq_sig	: std_logic;


	component melodychime_sg
	generic(
		CLOCK_EDGE		: std_logic;
		RESET_LEVEL		: std_logic;
		ENVELOPE_TC		: integer				-- エンベロープ時定数(一次遅れ系,t=0.5秒)
	);
	port(
		reset			: in  std_logic;
		clk				: in  std_logic;
		reg_div			: in  std_logic_vector(7 downto 0);
		reg_note		: in  std_logic;
		reg_write		: in  std_logic;

		timing_10us		: in  std_logic;
		timing_1ms		: in  std_logic;

		wave_out		: out std_logic_vector(15 downto 0)
	);
	end component;
	signal slot0_wav_sig	: std_logic_vector(15 downto 0);
	signal slot1_wav_sig	: std_logic_vector(15 downto 0);


	signal wav_add_sig		: std_logic_vector(9 downto 0);
	signal pcm_sig			: std_logic_vector(9 downto 0);
	signal add_sig			: std_logic_vector(pcm_sig'left+1 downto 0);
	signal dse_reg			: std_logic_vector(add_sig'left-1 downto 0);
	signal dacout_reg		: std_logic;

begin

	-- タイミングパルス生成 

	process (clk, reset) begin
		if (reset = RESET_LEVEL) then
			count10us <= 0;
			count1ms  <= 0;
			timing_10us_reg <= '0';
			timing_1ms_reg  <= '0';
			tempo_led_reg   <= '0';

		elsif (clk'event and clk = CLOCK_EDGE) then
			if (count10us = 0) then
				count10us <= CLOCKDIV_NUM-1;
				if (count1ms = 0) then
					count1ms <= 99;
				else 
					count1ms <= count1ms - 1;
				end if;
			else
				count10us <= count10us - 1;
			end if;

			if (count10us = 0) then
				timing_10us_reg <= '1';
			else 
				timing_10us_reg <= '0';
			end if;

			if (count10us = 0 and count1ms = 0) then
				timing_1ms_reg <= '1';
			else 
				timing_1ms_reg <= '0';
			end if;

			if (tempo_sig = '1') then
				tempo_led_reg <= not tempo_led_reg;
			end if;

		end if;
	end process;

	timing_1ms_out <= timing_1ms_reg;

	tempo_led <= tempo_led_reg;


	-- スタートキー入力 

	process (clk, reset) begin
		if (reset = RESET_LEVEL) then
			start_in_reg <= "000";
		elsif (clk'event and clk = CLOCK_EDGE) then
			if (timing_1ms_reg = '1') then
				start_in_reg <= start_in_reg(1 downto 0) & (not start);
			end if;
		end if;
	end process;

	start_sig <= '1' when(start_in_reg(2 downto 1) = "01") else '0';


	-- シーケンサインスタンス 

	U_SEQ : melodychime_seq
	generic map (
		CLOCK_EDGE		=> CLOCK_EDGE,
		RESET_LEVEL		=> RESET_LEVEL,
		TEMPO_TC		=> 357					-- テンポカウンタ(357ms/Tempo=84) 
	)
	port map (
		reset			=> reset,
		clk				=> clk,
		timing_1ms		=> timing_1ms_reg,
		tempo_out		=> tempo_sig,
		test_score_addr	=> test_score_led,		-- test 

		start			=> start_sig,

		slot_div		=> slot_div_sig,
		slot_note		=> slot_note_sig,
		slot0_wrreq		=> slot0_wrreq_sig,
		slot1_wrreq		=> slot1_wrreq_sig
	);


	-- 音源スロットインスタンス 

	U_SG0 : melodychime_sg
	generic map (
		CLOCK_EDGE		=> CLOCK_EDGE,
		RESET_LEVEL		=> RESET_LEVEL,
		ENVELOPE_TC		=> 28000				-- エンベロープ時定数(一次遅れ系,t=0.5秒)
	)
	port map (
		reset			=> reset,
		clk				=> clk,
		reg_div			=> slot_div_sig,
		reg_note		=> slot_note_sig,
		reg_write		=> slot0_wrreq_sig,

		timing_10us		=> timing_10us_reg,
		timing_1ms		=> timing_1ms_reg,

		wave_out		=> slot0_wav_sig
	);

	U_SG1 : melodychime_sg
	generic map (
		CLOCK_EDGE		=> CLOCK_EDGE,
		RESET_LEVEL		=> RESET_LEVEL,
		ENVELOPE_TC		=> 28000				-- エンベロープ時定数(一次遅れ系,t=0.5秒)
	)
	port map (
		reset			=> reset,
		clk				=> clk,
		reg_div			=> slot_div_sig,
		reg_note		=> slot_note_sig,
		reg_write		=> slot1_wrreq_sig,

		timing_10us		=> timing_10us_reg,
		timing_1ms		=> timing_1ms_reg,

		wave_out		=> slot1_wav_sig
	);


	-- 波形加算と1bitDSM-DAC

	wav_add_sig <= (slot0_wav_sig(15) & slot0_wav_sig(15 downto 7)) + (slot1_wav_sig(15) & slot1_wav_sig(15 downto 7));

	pcm_sig(9) <= not wav_add_sig(9);
	pcm_sig(8 downto 0) <= wav_add_sig(8 downto 0);

	add_sig <= ('0' & pcm_sig) + ('0' & dse_reg);

	process (clk, reset) begin
		if (reset = RESET_LEVEL) then
			dse_reg    <= (others=>'0');
			dacout_reg <= '0';

		elsif (clk'event and clk=CLOCK_EDGE) then
			dse_reg    <= add_sig(add_sig'left-1 downto 0);
			dacout_reg <= add_sig(add_sig'left);

		end if;
	end process;

	aud_l_out <= dacout_reg;
	aud_r_out <= dacout_reg;


end RTL;
