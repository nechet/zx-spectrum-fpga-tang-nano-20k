#!/usr/bin/env python3
"""Soviet -> Western part substitution for the Krasnodar-48 schematic.

Used by easyeda_sch_to_kicad.py --us to emit a second KiCad project in which
every device carries its Western part number instead of the Soviet one.

Every substitution below is **pin-for-pin identical** to the part the board was
drawn with: the pinouts were checked against the pin numbers and pin names
carried in the EasyEDA source itself, not just against a cross-reference table.
That is what makes the swap safe -- the netlist is unchanged, only the
identities are.  See Tools/part-equivalents.md for the evidence and sources.
"""

# Soviet value in the schematic -> (Western part, description)
PARTS = {
    # --- TTL, К555/КР555 -> 74LS ---------------------------------------------
    'К555ЛН1':   ('74LS04',   'Hex inverter'),
    'К555ЛА3':   ('74LS00',   'Quad 2-input NAND gate'),
    'К555ЛА4':   ('74LS10',   'Triple 3-input NAND gate'),
    'К555ЛЕ1':   ('74LS02',   'Quad 2-input NOR gate'),
    'К555ЛИ1':   ('74LS08',   'Quad 2-input AND gate'),
    'К555ЛЛ1':   ('74LS32',   'Quad 2-input OR gate'),
    'К555ЛП5':   ('74LS86',   'Quad 2-input XOR gate'),
    'К555ТМ2':   ('74LS74',   'Dual D flip-flop, preset and clear'),
    'К555ТМ8':   ('74LS175',  'Quad D flip-flop, common clock and clear'),
    'К555ИР16':  ('74LS295',  '4-bit universal shift register, 3-state'),
    'К555КП2':   ('74LS153',  'Dual 4-to-1 multiplexer'),
    'К555КП11A': ('74LS257',  'Quad 2-to-1 multiplexer, 3-state'),
    'К555КП12':  ('74LS253',  'Dual 4-to-1 multiplexer, 3-state'),
    'К555КП13':  ('74LS298',  'Quad 2-input multiplexer with storage'),
    'К555КП14':  ('74LS258',  'Quad 2-to-1 multiplexer, inverting, 3-state'),
    'КР555КП16': ('74LS157',  'Quad 2-to-1 multiplexer'),

    # --- TTL, К1533 -> 74ALS -------------------------------------------------
    'К1533ИД4':  ('74ALS155', 'Dual 2-to-4 decoder / demultiplexer'),
    'К1533ИЕ7':  ('74ALS193', '4-bit up/down binary counter'),

    # --- CMOS, К561 -> CD4000B -----------------------------------------------
    # CD4069UB, not the CD4049 that older Soviet handbooks list: the '4049 is a
    # 16-pin buffer with a different pinout and will not drop in.
    'К561ЛА7':   ('CD4011B',  'Quad 2-input NAND gate, CMOS'),
    'К561ЛЕ5':   ('CD4001B',  'Quad 2-input NOR gate, CMOS'),
    'К561ЛН2':   ('CD4069UB', 'Hex inverter, CMOS (NOT CD4049 - different pinout)'),
    'К561ТМ2':   ('CD4013B',  'Dual D flip-flop, CMOS'),
    'К561ИЕ10':  ('CD4520B',  'Dual 4-bit binary counter, CMOS'),
    'К561ИР2':   ('CD4015B',  'Dual 4-stage shift register, CMOS'),

    # --- LSI and memory ------------------------------------------------------
    'КР580ВВ55': ('8255A',    'Programmable peripheral interface (Intel 8255A)'),
    'КР565РУ5Д': ('4164',     '64K x 1 DRAM, +5V only'),
    # The 16K bank is drawn on the 4164 pinout with A7 (pin 9) tied low, exactly
    # so that a 64K part can be fitted -- which is what the board's own README
    # recommends.  So the Western part for this position is also a 4164.
    'КР565РУ6Г': ('4164',     '16K x 1 DRAM position; a 4164 fits, A7 is tied low'),

    # --- discrete ------------------------------------------------------------
    # КТ361 is PNP but its leads are E-C-B, which is NOT the 2N3906 (E-B-C) or
    # BC557 (C-B-E) order.  The part is renamed but the footprint is left for
    # the user to choose, because the land pattern has to match the lead order.
    'КТ361Б':    ('2N3906',   'PNP transistor - CHECK LEAD ORDER, КТ361 is E-C-B'),
}

# EasyEDA package -> KiCad footprint.  Only unambiguous matches are listed; a
# package that is not here keeps an empty Footprint field rather than being
# given a land pattern that is nearly but not quite right.
FOOTPRINTS = {
    'DIP-14_STD': 'Package_DIP:DIP-14_W7.62mm',
    'DIP-16_STD': 'Package_DIP:DIP-16_W7.62mm',
    'DIP-28_STD': 'Package_DIP:DIP-28_W15.24mm',
    'DIP-40_STD': 'Package_DIP:DIP-40_W15.24mm',

    'R_0.125_7.62': 'Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P7.62mm_Horizontal',
    'R_0.125_5.08': 'Resistor_THT:R_Axial_DIN0204_L3.6mm_D1.6mm_P5.08mm_Horizontal',
    'R_0.125_V_TH': 'Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P2.54mm_Vertical',

    'CAP_TH_2.54':  'Capacitor_THT:C_Disc_D5.0mm_W2.5mm_P2.50mm',
    'CAP_TH_5.08':  'Capacitor_THT:C_Disc_D5.0mm_W2.5mm_P5.00mm',
    'CAP-TH_L5.08': 'Capacitor_THT:C_Disc_D5.0mm_W2.5mm_P5.00mm',
    'CAP-TH_L7.0-W3.0-P5.00-D0.9': 'Capacitor_THT:C_Disc_D7.0mm_W2.5mm_P5.00mm',
    'CAP-TH_BD6.3-P2.50-D1.0-FD':  'Capacitor_THT:CP_Radial_D6.3mm_P2.50mm',
    'CAP-TH_BD5.0-P2.00-D0.8-FD':  'Capacitor_THT:CP_Radial_D5.0mm_P2.00mm',

    'D_TH_5.08': 'Diode_THT:D_DO-35_SOD27_P7.62mm_Horizontal',

    'OSC-49U-1': 'Crystal:Crystal_HC49-U_Vertical',

    'HDR-TH_2P-P2.54-V-M': 'Connector_PinHeader_2.54mm:PinHeader_1x02_P2.54mm_Vertical',
    'HDR-TH_3P-P2.54-V-M': 'Connector_PinHeader_2.54mm:PinHeader_1x03_P2.54mm_Vertical',
    'HDR-M-2.54_1X1':      'Connector_PinHeader_2.54mm:PinHeader_1x01_P2.54mm_Vertical',
    'MOLEX-1X4': 'Connector_Molex:Molex_KK-254_AE-6410-04A_1x04_P2.54mm_Vertical',
}

# Packages deliberately left without a KiCad footprint, and why.
FOOTPRINT_NOTES = {
    'CAP_TH_3.68': 'no 3.68 mm-pitch disc capacitor in the KiCad libraries',
    'CAP-TH_BD6.3-P6.00-D0.8-FD': 'KiCad has D6.3 mm radial only at 2.50 mm pitch',
    'D_TH_2.54_V': 'vertical DO-35 land pattern depends on which lead is up',
    'KT315_STD': 'КТ361 lead order is E-C-B; pick a land pattern to match the '
                 'transistor you actually fit',
    'SYS_CONN_32X2_5.08': 'board-specific 2x32 expansion connector',
}


def western(value):
    """Western part number for a Soviet value, or None if there is no mapping."""
    return PARTS.get(value, (None, None))[0]


def description(value):
    return PARTS.get(value, (None, ''))[1]


def footprint(package):
    return FOOTPRINTS.get(package, '')


# -----------------------------------------------------------------------------
# ANSI drafting: gate shapes, box labels and datasheet pin names.
# -----------------------------------------------------------------------------

# Western part -> ANSI distinctive shape.  Everything not listed here keeps a
# rectangular body, which is what US practice uses for MSI and LSI anyway.
GATES = {
    '74LS00':   'nand',
    '74LS10':   'nand',
    '74LS02':   'nor',
    '74LS04':   'not',
    '74LS08':   'and',
    '74LS32':   'or',
    '74LS86':   'xor',
    'CD4011B':  'nand',
    'CD4001B':  'nor',
    'CD4069UB': 'not',
}

# GOST qualifier inside a rectangular body -> the US equivalent label.
# Gate qualifiers are dropped entirely: the shape carries the meaning.
BOX_LABELS = {
    'MS': 'MUX', 'MX': 'MUX', 'DC': 'DEC', 'RG': 'SRG',
    'CT2': 'CTR', 'T': 'DFF', 'TT': 'DFF',
    '&': None, '1': None, '=1': None,
}

# Datasheet pin names, by Western part number.  Only pins that need renaming
# are listed; anything absent keeps the name the schematic already carries.
# Hidden power pins are never renamed -- KiCad connects those by name.
# "~" marks an overbar, written as ~{...} in the KiCad symbol.
PIN_NAMES = {
    # Parts with several KiCad units carry no unit suffix on their pin names:
    # each unit shows only its own pins, so "CLR1" would be redundant -- and it
    # overflows the narrow flip-flop bodies.
    '74LS74': {'1': '~CLR', '2': 'D', '3': 'CLK', '4': '~PRE', '5': 'Q',
               '6': '~Q', '8': '~Q', '9': 'Q', '10': '~PRE', '11': 'CLK',
               '12': 'D', '13': '~CLR'},
    '74LS175': {'1': '~CLR', '2': 'Q1', '3': '~Q1', '4': 'D1', '5': 'D2',
                '6': '~Q2', '7': 'Q2', '9': 'CLK', '10': 'Q3', '11': '~Q3',
                '12': 'D3', '13': 'D4', '14': '~Q4', '15': 'Q4'},
    '74ALS193': {'1': 'B', '2': 'QB', '3': 'QA', '4': 'DOWN', '5': 'UP',
                 '6': 'QC', '7': 'QD', '9': 'D', '10': 'C', '11': '~LOAD',
                 '12': '~CO', '13': '~BO', '14': 'CLR', '15': 'A'},
    '74ALS155': {'1': '~1G', '2': '1C', '3': 'B', '4': '~1Y3', '5': '~1Y2',
                 '6': '~1Y1', '7': '~1Y0', '9': '~2Y0', '10': '~2Y1',
                 '11': '~2Y2', '12': '~2Y3', '13': 'A', '14': '~2C',
                 '15': '~2G'},
    '74LS153': {'1': '~1G', '2': 'B', '3': '1C3', '4': '1C2', '5': '1C1',
                '6': '1C0', '7': '1Y', '9': '2Y', '10': '2C0', '11': '2C1',
                '12': '2C2', '13': '2C3', '14': 'A', '15': '~2G'},
    '74LS253': {'1': '~1G', '2': 'B', '3': '1C3', '4': '1C2', '5': '1C1',
                '6': '1C0', '7': '1Y', '9': '2Y', '10': '2C0', '11': '2C1',
                '12': '2C2', '13': '2C3', '14': 'A', '15': '~2G'},
    '74LS157': {'1': 'A/~B', '2': '1A', '3': '1B', '4': '1Y', '5': '2A',
                '6': '2B', '7': '2Y', '9': '3Y', '10': '3B', '11': '3A',
                '12': '4Y', '13': '4B', '14': '4A', '15': '~G'},
    '74LS257': {'1': 'A/~B', '2': '1A', '3': '1B', '4': '1Y', '5': '2A',
                '6': '2B', '7': '2Y', '9': '3Y', '10': '3B', '11': '3A',
                '12': '4Y', '13': '4B', '14': '4A', '15': '~OE'},
    '74LS258': {'1': 'A/~B', '2': '1A', '3': '1B', '4': '~1Y', '5': '2A',
                '6': '2B', '7': '~2Y', '9': '~3Y', '10': '3B', '11': '3A',
                '12': '~4Y', '13': '4B', '14': '4A', '15': '~OE'},
    '74LS295': {'1': 'SER', '2': 'A', '3': 'B', '4': 'C', '5': 'D',
                '6': 'MODE', '8': 'OE', '9': 'CLK', '10': 'QD', '11': 'QC',
                '12': 'QB', '13': 'QA'},
    '74LS298': {'1': 'B2', '2': 'A2', '3': 'A1', '4': 'B1', '5': 'C2',
                '6': 'D2', '7': 'D1', '9': 'C1', '10': 'WS', '11': 'CLK',
                '12': 'QD', '13': 'QC', '14': 'QB', '15': 'QA'},
    'CD4013B': {'1': 'Q', '2': '~Q', '3': 'CLK', '4': 'RST', '5': 'D',
                '6': 'SET', '8': 'SET', '9': 'D', '10': 'RST',
                '11': 'CLK', '12': '~Q', '13': 'Q'},
    'CD4015B': {'1': 'CLK', '2': 'Q4', '3': 'Q3', '4': 'Q2', '5': 'Q1',
                '6': 'RST', '7': 'D', '9': 'CLK', '10': 'Q4', '11': 'Q3',
                '12': 'Q2', '13': 'Q1', '14': 'RST', '15': 'D'},
    'CD4520B': {'1': 'CLK', '2': 'EN', '3': 'Q0', '4': 'Q1', '5': 'Q2',
                '6': 'Q3', '7': 'RST', '9': 'CLK', '10': 'EN', '11': 'Q0',
                '12': 'Q1', '13': 'Q2', '14': 'Q3', '15': 'RST'},
    '8255A': {'5': '~RD', '6': '~CS', '35': 'RESET', '36': '~WR'},
    '4164': {'2': 'DIN', '3': '~WE', '4': '~RAS', '14': 'DOUT', '15': '~CAS'},
    '27C128': {'1': 'VPP', '20': '~CE', '22': '~OE', '27': '~PGM'},
    'Z80': {'6': 'CLK', '16': '~INT', '17': '~NMI', '18': '~HALT',
            '19': '~MREQ', '20': '~IORQ', '21': '~RD', '22': '~WR',
            '23': '~BUSAK', '24': '~WAIT', '25': '~BUSRQ', '26': '~RESET',
            '27': '~M1', '28': '~RFSH'},
}


def gate_kind(value):
    return GATES.get(value)


def box_label(text):
    """US label for a GOST qualifier; '' means drop it, None means keep as is."""
    if text in BOX_LABELS:
        return BOX_LABELS[text] or ''
    return None


def pin_name(value, number, current):
    """Datasheet pin name, with a leading '-' or '~' turned into an overbar."""
    name = PIN_NAMES.get(value, {}).get(number)
    if name is None:
        name = current.replace('&#126;', '~')
        if not name.startswith(('-', '~')):
            return name
    return _overbar(name)


def _overbar(name):
    n = name.lstrip('-~')
    return '~{%s}' % n if n != name else name
