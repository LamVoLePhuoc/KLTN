import os

register_map = {r + str(i): i for r in ("f", "x") for i in range(32)}

# Define standard funct7 encodings
Rf7  = "0000000"  # Normal R-type instructions
Rf7n = "0100000"  # "Negate" type (e.g., sub, sra)
Rf7m = "0000001"  # Multiply/Divide (M-extension)

# Define standard control and status registers
fflags  = "000000000001"
frm     = "000000000010"
fcsr    = "000000000011"
cycle   = "110000000000"
time    = "110000000001"
instret = "110000000010"

# Build CSR map: name -> integer address (12-bit)
csr_map = {
    "fflags": int(fflags, 2),
    "frm": int(frm, 2),
    "fcsr": int(fcsr, 2),
    "cycle": int(cycle, 2),
    "time": int(time, 2),
    "instret": int(instret, 2),
}

# Mapping rounding mode
rounding_mode_map = {
    "RNE": "000",
    "RTZ": "001",
    "RDN": "010",
    "RUP": "011",
    "RMM": "100",
    "DYN": "111"
}

FPU_SPECIAL_RULES = {
    # xD, fS1, fS2
    "feq.d":   ("x", "f", "f"),
    "flt.d":   ("x", "f", "f"),
    "fle.d":   ("x", "f", "f"),

    # xD, fS
    "fclass.d": ("x", "f"),

    # xD, fS
    "fcvt.w.d":  ("x", "f"),
    "fcvt.wu.d": ("x", "f"),
    "fcvt.l.d":  ("x", "f"),
    "fcvt.lu.d": ("x", "f"),
    "fmv.x.d":   ("x", "f"),

    # fD, xS
    "fcvt.d.w":  ("f", "x"),
    "fcvt.d.wu": ("f", "x"),
    "fcvt.d.l":  ("f", "x"),
    "fcvt.d.lu": ("f", "x"),
    "fmv.d.x":   ("f", "x"),
}

# Define instruction formats and encoding info
instruction_map = {
    # Load
    "lb":     {"opcode": "0000011", "funct3": "000", "type": "I"},
    "lh":     {"opcode": "0000011", "funct3": "001", "type": "I"},
    "lw":     {"opcode": "0000011", "funct3": "010", "type": "I"},
    "ld":     {"opcode": "0000011", "funct3": "011", "type": "I"},
    "lbu":    {"opcode": "0000011", "funct3": "100", "type": "I"},
    "lhu":    {"opcode": "0000011", "funct3": "101", "type": "I"},
    "lwu":    {"opcode": "0000011", "funct3": "110", "type": "I"},
    
    # Store
    "sb":     {"opcode": "0100011", "funct3": "000", "type": "S"},
    "sh":     {"opcode": "0100011", "funct3": "001", "type": "S"},
    "sw":     {"opcode": "0100011", "funct3": "010", "type": "S"},
    "sd":     {"opcode": "0100011", "funct3": "011", "type": "S"},

    # I-type
    "addi":   {"opcode": "0010011", "funct3": "000", "type": "I"},
    "slti":   {"opcode": "0010011", "funct3": "010", "type": "I"},
    "sltiu":  {"opcode": "0010011", "funct3": "011", "type": "I"},
    "xori":   {"opcode": "0010011", "funct3": "100", "type": "I"},
    "ori":    {"opcode": "0010011", "funct3": "110", "type": "I"},
    "andi":   {"opcode": "0010011", "funct3": "111", "type": "I"},
    "slli":   {"opcode": "0010011", "funct3": "001", "funct6": "000000", "type": "I"},
    "srli":   {"opcode": "0010011", "funct3": "101", "funct6": "000000", "type": "I"},
    "srai":   {"opcode": "0010011", "funct3": "101", "funct6": "010000", "type": "I"},
    "addiw":  {"opcode": "0011011", "funct3": "000", "type": "I"},
    "slliw":  {"opcode": "0011011", "funct3": "001", "funct7": Rf7, "type": "I"},
    "srliw":  {"opcode": "0011011", "funct3": "101", "funct7": Rf7, "type": "I"},
    "sraiw":  {"opcode": "0011011", "funct3": "101", "funct7": Rf7n, "type": "I"},
    "jalr":   {"opcode": "1100111", "funct3": "000", "type": "I"},

    # R-type
    "add":    {"opcode": "0110011", "funct3": "000", "funct7": Rf7, "type": "R"},
    "sub":    {"opcode": "0110011", "funct3": "000", "funct7": Rf7n, "type": "R"},
    "sll":    {"opcode": "0110011", "funct3": "001", "funct7": Rf7, "type": "R"},
    "slt":    {"opcode": "0110011", "funct3": "010", "funct7": Rf7, "type": "R"},
    "sltu":   {"opcode": "0110011", "funct3": "011", "funct7": Rf7, "type": "R"},
    "xor":    {"opcode": "0110011", "funct3": "100", "funct7": Rf7, "type": "R"},
    "srl":    {"opcode": "0110011", "funct3": "101", "funct7": Rf7, "type": "R"},
    "sra":    {"opcode": "0110011", "funct3": "101", "funct7": Rf7n, "type": "R"},
    "or":     {"opcode": "0110011", "funct3": "110", "funct7": Rf7, "type": "R"},
    "and":    {"opcode": "0110011", "funct3": "111", "funct7": Rf7, "type": "R"},
    "mul":    {"opcode": "0110011", "funct3": "000", "funct7": Rf7m, "type": "R"},
    "mulh":   {"opcode": "0110011", "funct3": "001", "funct7": Rf7m, "type": "R"},
    "mulhsu": {"opcode": "0110011", "funct3": "010", "funct7": Rf7m, "type": "R"},
    "mulhu":  {"opcode": "0110011", "funct3": "011", "funct7": Rf7m, "type": "R"},
    "div":    {"opcode": "0110011", "funct3": "100", "funct7": Rf7m, "type": "R"},
    "divu":   {"opcode": "0110011", "funct3": "101", "funct7": Rf7m, "type": "R"},
    "rem":    {"opcode": "0110011", "funct3": "110", "funct7": Rf7m, "type": "R"},
    "remu":   {"opcode": "0110011", "funct3": "111", "funct7": Rf7m, "type": "R"},
    "addw":   {"opcode": "0111011", "funct3": "000", "funct7": Rf7, "type": "R"},
    "subw":   {"opcode": "0111011", "funct3": "000", "funct7": Rf7n, "type": "R"},
    "sllw":   {"opcode": "0111011", "funct3": "001", "funct7": Rf7, "type": "R"},
    "srlw":   {"opcode": "0111011", "funct3": "101", "funct7": Rf7, "type": "R"},
    "sraw":   {"opcode": "0111011", "funct3": "101", "funct7": Rf7n, "type": "R"},
    "mulw":   {"opcode": "0111011", "funct3": "000", "funct7": Rf7m, "type": "R"},
    "divw":   {"opcode": "0111011", "funct3": "100", "funct7": Rf7m, "type": "R"},
    "divuw":  {"opcode": "0111011", "funct3": "101", "funct7": Rf7m, "type": "R"},
    "remw":   {"opcode": "0111011", "funct3": "110", "funct7": Rf7m, "type": "R"},
    "remuw":  {"opcode": "0111011", "funct3": "111", "funct7": Rf7m, "type": "R"},

    # B-type
    "beq":    {"opcode": "1100011", "funct3": "000", "type": "B"},
    "bne":    {"opcode": "1100011", "funct3": "001", "type": "B"},
    "blt":    {"opcode": "1100011", "funct3": "100", "type": "B"},
    "bge":    {"opcode": "1100011", "funct3": "101", "type": "B"},
    "bltu":   {"opcode": "1100011", "funct3": "110", "type": "B"},
    "bgeu":   {"opcode": "1100011", "funct3": "111", "type": "B"},

    # J-type
    "jal":    {"opcode": "1101111", "type": "J"},

    # U-type
    "lui":    {"opcode": "0110111", "type": "U"},
    "auipc":  {"opcode": "0010111", "type": "U"},

    # CSR-type
    "csrrw":  {"opcode": "1110011", "funct3": "001", "type": "CSR"},
    "csrrs":  {"opcode": "1110011", "funct3": "010", "type": "CSR"},
    "csrrc":  {"opcode": "1110011", "funct3": "011", "type": "CSR"},
    "ecall":  {"opcode": "1110011", "funct25": "0000000000000000000000000", "type": "CSR"},
    "ebreak": {"opcode": "1110011", "funct25": "0000000000010000000000000", "type": "CSR"},
    "csrrwi": {"opcode": "1110011", "funct3": "101", "type": "CSR-I"},
    "csrrsi": {"opcode": "1110011", "funct3": "110", "type": "CSR-I"},
    "csrrci": {"opcode": "1110011", "funct3": "111", "type": "CSR-I"},

    # FENCE-type
    "fence":  {"opcode": "0001111", "funct3": "000", "type": "FENCE"},
    "fence.i":{"opcode": "0001111", "funct3": "001", "type": "FENCE"},

    # NOP command
    "nop": {"opcode": "1111111", "type": "NOP"},

    # FPU commands
    "fld": {"opcode": "0000111", "funct3": "011", "type": "I_float"},
    "fsd": {"opcode": "0100111", "funct3": "011", "type": "S_float"},

    "fmadd.d":  {"opcode": "1000011", "funct2": "01", "type": "R4_float"},
    "fmsub.d":  {"opcode": "1000111", "funct2": "01", "type": "R4_float"},
    "fnmsub.d": {"opcode": "1001011", "funct2": "01", "type": "R4_float"},
    "fnmadd.d": {"opcode": "1001111", "funct2": "01", "type": "R4_float"},

    "fadd.d": {"opcode": "1010011", "funct7": "0000001", "type": "R_rm_float"},
    "fsub.d": {"opcode": "1010011", "funct7": "0000101", "type": "R_rm_float"},
    "fmul.d": {"opcode": "1010011", "funct7": "0001001", "type": "R_rm_float"},
    "fdiv.d": {"opcode": "1010011", "funct7": "0001101", "type": "R_rm_float"},
    "fsqrt.d": {"opcode": "1010011", "funct7": "0101101", "type": "SQRT_float"},

    "fsgnj.d":  {"opcode": "1010011", "funct7": "0010001", "funct3": "000", "type": "R_float"},
    "fsgnjn.d": {"opcode": "1010011", "funct7": "0010001", "funct3": "001", "type": "R_float"},
    "fsgnjx.d": {"opcode": "1010011", "funct7": "0010001", "funct3": "010", "type": "R_float"},

    "fmin.d": {"opcode": "1010011", "funct7": "0010101", "funct3": "000", "type": "R_float"},
    "fmax.d": {"opcode": "1010011", "funct7": "0010101", "funct3": "001", "type": "R_float"},

    "feq.d": {"opcode": "1010011", "funct7": "1010001", "funct3": "010", "type": "R_float"},
    "flt.d": {"opcode": "1010011", "funct7": "1010001", "funct3": "001", "type": "R_float"},
    "fle.d": {"opcode": "1010011", "funct7": "1010001", "funct3": "000", "type": "R_float"},

    "fcvt.w.d":  {"opcode": "1010011", "funct7": "1100001", "rs2": "00000", "type": "RCVT_rm_float"},
    "fcvt.wu.d": {"opcode": "1010011", "funct7": "1100001", "rs2": "00001", "type": "RCVT_rm_float"},
    "fcvt.d.w":  {"opcode": "1010011", "funct7": "1101001", "rs2": "00000", "type": "RCVT_rm_float"},
    "fcvt.d.wu": {"opcode": "1010011", "funct7": "1101001", "rs2": "00001", "type": "RCVT_rm_float"},
    "fcvt.s.d":  {"opcode": "1010011", "funct7": "0100000", "rs2": "00001", "type": "RCVT_rm_float"},
    "fcvt.d.s":  {"opcode": "1010011", "funct7": "0100001", "rs2": "00000", "type": "RCVT_rm_float"},
    "fcvt.l.d":  {"opcode": "1010011", "funct7": "1100001", "rs2": "00010", "type": "RCVT_rm_float"},
    "fcvt.lu.d": {"opcode": "1010011", "funct7": "1100001", "rs2": "00011", "type": "RCVT_rm_float"},
    "fcvt.d.l":  {"opcode": "1010011", "funct7": "1101001", "rs2": "00010", "type": "RCVT_rm_float"},
    "fcvt.d.lu": {"opcode": "1010011", "funct7": "1101001", "rs2": "00011", "type": "RCVT_rm_float"},

    "fmv.x.d": {"opcode": "1010011", "funct7": "1110001", "rs2": "00000", "funct3": "000", "type": "RCVT_float"},
    "fmv.d.x": {"opcode": "1010011", "funct7": "1111001", "rs2": "00000", "funct3": "000", "type": "RCVT_float"},

    "fclass.d": {"opcode": "1010011", "funct7": "1110001", "rs2": "00000", "funct3": "001", "type": "RCVT_float"}
}

def is_x(reg): return reg.startswith("x")
def is_f(reg): return reg.startswith("f")
def is_register(tok):
    return tok in register_map
    
def extract_base_reg(mem_op):
    # 2(x3) → x3
    if "(" not in mem_op or not mem_op.endswith(")"):
        raise ValueError(f"Invalid memory operand: {mem_op}")
    return mem_op[mem_op.find("(")+1:-1]

def check_register_class(mnemonic, tokens, instr):

    # fld / fsd : fD, imm(xS)
    if mnemonic in ("fld", "fsd"):
        if not is_f(tokens[1]):
            raise ValueError(f"{mnemonic}: destination must be f register\n→ {instr}")

        base = extract_base_reg(tokens[2])
        if not is_x(base):
            raise ValueError(f"{mnemonic}: base register must be x register\n→ {instr}")
        return

    # Special explicit rules
    if mnemonic in FPU_SPECIAL_RULES:
        rule = FPU_SPECIAL_RULES[mnemonic]
        for idx, expected in enumerate(rule, start=1):
            reg = tokens[idx]
            if expected == "x" and not is_x(reg):
                raise ValueError(f"{mnemonic}: operand {idx} must be x register\n→ {instr}")
            if expected == "f" and not is_f(reg):
                raise ValueError(f"{mnemonic}: operand {idx} must be f register\n→ {instr}")
        return

    # Generic FPU instruction
    if mnemonic.startswith("f"):
        for t in tokens[1:]:
            if "(" in t:
                continue
            if is_register(t) and not is_f(t):
                raise ValueError(
                    f"{mnemonic}: FPU instruction cannot use x register\n→ {instr}"
                )
        return

    # Generic CPU instruction
    for t in tokens[1:]:
        if "(" in t:
            base = extract_base_reg(t)
            if not is_x(base):
                raise ValueError(
                    f"{mnemonic}: base register must be x register\n→ {instr}"
                )
        elif is_register(t):
            if not is_x(t):
                raise ValueError(
                    f"{mnemonic}: CPU instruction cannot use f register\n→ {instr}"
                )

def parse_labels(lines):
    label_addr = {}
    instr_lines = []
    current_index = 0
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if ":" in line:
            label = line.split(":")[0].strip()
            # Check duplicate label (case-insensitive)
            for existing_label in label_addr:
                if existing_label.lower() == label.lower():
                    raise ValueError(f"Duplicate label found: {label}\n→ Instruction: {line}")
            rest = line.split(":")[1].strip()
            if rest:
                # Label and instruction on the same line
                label_addr[label] = current_index
                instr_lines.append(rest)
                current_index += 1
            else:
                # Label alone on a line → assign to the next instruction
                label_addr[label] = current_index
        else:
            instr_lines.append(line)
            current_index += 1
    return instr_lines, label_addr

def parse_csr_token(token):
    """
    Accept:
     - named CSR like 'fflags', 'cycle' (case-insensitive)
     - numeric CSR in hex (0xB00) or decimal (e.g. 1792)
    Returns integer 0..0xfff (12-bit)
    """
    t = token.strip().lower()
    # named
    if t in csr_map:
        return csr_map[t]
    # hex
    if t.startswith("0x"):
        try:
            val = int(t, 16)
        except ValueError:
            raise ValueError(f"Invalid CSR number: {token}")
        if not (0 <= val < (1 << 12)):
            raise ValueError(f"CSR value out of 12-bit range: {token}")
        return val
    # decimal
    try:
        val = int(t, 10)
        if not (0 <= val < (1 << 12)):
            raise ValueError(f"CSR value out of 12-bit range: {token}")
        return val
    except ValueError:
        raise ValueError(f"Unknown CSR token or name: {token}")

def to_bin(val, bits):
    """Convert an integer to a binary string of fixed width."""
    if val < 0:
        val = (1 << bits) + val
    return format(val, f"0{bits}b")

def to_hex(binstr):
    """Convert a binary string to 32-bit hexadecimal format."""
    return f"{int(binstr, 2):08x}"

def encode_instruction(instr, current_index, label_addr, rm_bin):
    tokens = instr.replace(",", "").split()
    mnemonic = tokens[0].lower()
    check_register_class(mnemonic, tokens, instr)
    if mnemonic not in instruction_map:
        raise ValueError(f"Unknown instruction: {mnemonic}\n→ Instruction: {instr}")
    spec = instruction_map[mnemonic]

    # Common syntax validation
    def check_reg(name):
        str_name = f"{name}"
        if str_name not in register_map:
            raise ValueError(f"Invalid register name: {str_name}\n→ Instruction: {instr}")

    # Validate token count by instruction type
    typ = spec["type"]
    tlen = len(tokens)
    if typ in ("R", "R_rm_float", "R_float") and tlen != 4:
        raise ValueError(f"Invalid syntax for {mnemonic}: expected 3 operands, got {tlen-1}\n→ Instruction: {instr}")
    if typ in ("I", "I_float") and not (3 <= tlen <= 4):
        raise ValueError(f"Invalid syntax for {mnemonic}: expected 2-3 operands, got {tlen-1}\n→ Instruction: {instr}")
    if typ in ("S", "S_float", "SQRT_float", "RCVT_rm_float", "RCVT_float") and tlen != 3:
        raise ValueError(f"Invalid syntax for {mnemonic}: expected 2 operands, got {tlen-1}\n→ Instruction: {instr}")
    if typ == "B" and tlen != 4:
        raise ValueError(f"Invalid syntax for {mnemonic}: expected 3 operands, got {tlen-1}\n→ Instruction: {instr}")
    if typ == "R4_float" and tlen != 5:
        raise ValueError(f"Invalid syntax for {mnemonic}: expected 4 operands, got {tlen-1}\n→ Instruction: {instr}")
    if typ in ("U", "J") and tlen != 3:
        raise ValueError(f"Invalid syntax for {mnemonic}: expected 2 operands, got {tlen-1}\n→ Instruction: {instr}")

    # Handle different instruction formats
    if spec["type"] == "S":
        # Format: imm[11:5] | rs2 | rs1 | funct3 | imm[4:0] | opcode
        check_reg(tokens[1])
        rs2 = register_map[tokens[1]]
        offset, rs1 = tokens[2].split("(")
        try:
            val = int(offset)
        except ValueError:
            raise ValueError(f"Invalid immediate value in: {instr}\n→ Instruction: {instr}")
        rs1 = register_map[rs1[:-1]]
        imm = to_bin(int(offset), 12)
        return to_hex(
            imm[:7] +
            to_bin(rs2, 5) +
            to_bin(rs1, 5) +
            spec["funct3"] +
            imm[7:] +
            spec["opcode"]
        )

    elif spec["type"] == "I":
        check_reg(tokens[1])
        rd = register_map[tokens[1]]
        # Handle both imm(rs1) and imm rs1 formats
        if "(" in tokens[2]:
            offset, rs1 = tokens[2].split("(")
            try:
                val = int(offset)
            except ValueError:
                raise ValueError(f"Invalid immediate value in: {instr}\n→ Instruction: {instr}")
            rs1 = register_map[rs1[:-1]]
            imm = to_bin(int(offset), 12)
        else:
            check_reg(tokens[2])
            rs1 = register_map[tokens[2]]
            imm = to_bin(int(tokens[3]), 12)

        if "funct6" not in spec and "funct7" not in spec:
            # Case 1: Standard I-type (addi, andi, ori, ...)
            # Format: imm[11:0] | rs1 | funct3 | rd | opcode
            return to_hex(
                imm +
                to_bin(rs1, 5) +
                spec["funct3"] +
                to_bin(rd, 5) +
                spec["opcode"]
            )
        elif "funct6" in spec:
            # Case 2: Shift immediate with funct6 (slli, srli, srai)
            # Format: funct6 | shamt[5:0] | rs1 | funct3 | rd | opcode
            shamt = to_bin(int(tokens[3]), 6)
            return to_hex(
                spec["funct6"] +
                shamt +
                to_bin(rs1, 5) +
                spec["funct3"] +
                to_bin(rd, 5) +
                spec["opcode"]
            )
        elif "funct7" in spec:
            # Case 3: Shift immediate with funct7 (slliw, srliw, sraiw)
            # Format: funct7 | shamt[4:0] | rs1 | funct3 | rd | opcode
            shamt = to_bin(int(tokens[3]), 5)
            return to_hex(
                spec["funct7"] +
                shamt +
                to_bin(rs1, 5) +
                spec["funct3"] +
                to_bin(rd, 5) +
                spec["opcode"]
            )

    elif spec["type"] == "R":
        # Format: funct7 | rs2 | rs1 | funct3 | rd | opcode
        check_reg(tokens[1])
        check_reg(tokens[2])
        check_reg(tokens[3])
        rd = register_map[tokens[1]]
        rs1 = register_map[tokens[2]]
        rs2 = register_map[tokens[3]]
        return to_hex(
            spec["funct7"] +
            to_bin(rs2, 5) +
            to_bin(rs1, 5) +
            spec["funct3"] +
            to_bin(rd, 5) +
            spec["opcode"]
        )

    elif spec["type"] == "B":
        # Format: imm[12] | imm[10:5] | rs2 | rs1 | funct3 | imm[4:1] | imm[11] | opcode
        check_reg(tokens[1])
        check_reg(tokens[2])
        rs1 = register_map[tokens[1]]
        rs2 = register_map[tokens[2]]
        label = tokens[3]
        if label not in label_addr:
            raise ValueError(f"Undefined label '{label}'\n→ Instruction: {instr}")
        target_line = label_addr[label]
        offset = (target_line - current_index) * 4
        imm = to_bin(offset, 13)
        return to_hex(
            imm[0] +                  # imm[12]
            imm[2:8] +                # imm[10:5]
            to_bin(rs2, 5) +
            to_bin(rs1, 5) +
            spec["funct3"] +
            imm[8:12] +               # imm[4:1]
            imm[1] +                  # imm[11]
            spec["opcode"]
        )

    elif spec["type"] == "J":
        # Format: imm[20] | imm[10:1] | imm[11] | imm[19:12] | rd | opcode
        check_reg(tokens[1])
        rd = register_map[tokens[1]]
        label = tokens[2]
        if label not in label_addr:
            raise ValueError(f"Undefined label '{label}'\n→ Instruction: {instr}")
        target_line = label_addr[label]
        offset = (target_line - current_index) * 4
        imm = to_bin(offset, 21)
        return to_hex(
            imm[0] +                  # imm[20]
            imm[10:20] +              # imm[10:1]
            imm[9] +                  # imm[11]
            imm[1:9] +                # imm[19:12]
            to_bin(rd, 5) +
            spec["opcode"]
        )

    elif spec["type"] == "U":
        # Format: imm[31:12] | rd | opcode
        check_reg(tokens[1])
        rd = register_map[tokens[1]]
        imm = to_bin(int(tokens[2]), 32)
        return to_hex(
            imm[-20:] +
            to_bin(rd, 5) +
            spec["opcode"]
        )
        
    elif spec["type"] == "CSR":
        if "funct25" in spec:
            return to_hex(
                spec["funct25"] +
                spec["opcode"]
            )
        else:
            # Format: csr | rs1 | funct3 | rd | opcode
            check_reg(tokens[1])
            check_reg(tokens[3])
            rd = register_map[tokens[1]]
            csr = tokens[2]
            rs1 = register_map[tokens[3]]
            csr_val = parse_csr_token(csr)
            return to_hex(
                to_bin(csr_val, 12) +
                to_bin(rs1, 5) +
                spec["funct3"] +
                to_bin(rd, 5) +
                spec["opcode"]
            )

    elif spec["type"] == "CSR-I":
        # Format: csr | zimm | funct3 | rd | opcode
        check_reg(tokens[1])
        rd = register_map[tokens[1]]
        csr = tokens[2]
        zimm = tokens[3]
        try:
            zimm = int(zimm, 0)
        except ValueError:
            raise ValueError(f"Invalid zimm immediate for CSR-I: {zimm}\n→ Instruction: {instr}")
        csr_val = parse_csr_token(csr)
        return to_hex(
            to_bin(csr_val, 12) +
            to_bin(int(zimm), 5) +
            spec["funct3"] +
            to_bin(rd, 5) +
            spec["opcode"]
        )

    elif spec["type"] == "FENCE":
        if mnemonic == "fence.i":
            # fence.i encoding is fixed: 0000000 00000 00000 001 00000 0001111
            return to_hex("00000000000000000001000000001111")
            
        # Format: 0000 | pred | succ | 00000 | funct3 | 00000 | opcode
        pred_str = "iorw"
        succ_str = "iorw"

        # Parse if args exist
        if len(tokens) == 3:
            pred_str = tokens[1].lower()
            succ_str = tokens[2].lower()
        elif len(tokens) == 2:
            pred_str = tokens[1].lower()

        # Convert pred/succ strings to 4-bit values
        def encode_ioset(s):
            bits = 0
            if "i" in s: bits |= (1 << 3)
            if "o" in s: bits |= (1 << 2)
            if "r" in s: bits |= (1 << 1)
            if "w" in s: bits |= (1 << 0)
            return bits

        pred_val = encode_ioset(pred_str)
        succ_val = encode_ioset(succ_str)

        return to_hex(
            "0000" +                              # funct4 (always 0000)
            to_bin(pred_val, 4) +                 # pred[3:0]
            to_bin(succ_val, 4) +                 # succ[3:0]
            "00000" +                             # rs1
            spec["funct3"] +
            "00000" +                             # rd
            spec["opcode"]
        )

    elif spec["type"] == "I_float":
        # I-type: imm[11:0] | rs1 | funct3 | rd | opcode
        rd = register_map[tokens[1]]
        offset, rs1 = tokens[2].split("(")
        rs1 = register_map[rs1[:-1]]
        imm = int(offset)
        return to_hex(
            to_bin(imm, 12) +
            to_bin(rs1, 5) +
            spec["funct3"] +
            to_bin(rd, 5) +
            spec["opcode"]
        )
    
    elif spec["type"] == "S_float":
        # S-type: imm[11:5] | rs2 | rs1 | funct3 | imm[4:0] | opcode
        rs2 = register_map[tokens[1]]
        offset, rs1 = tokens[2].split("(")
        rs1 = register_map[rs1[:-1]]
        imm = to_bin(int(offset), 12)
        return to_hex(
            imm[:7] +
            to_bin(rs2, 5) +
            to_bin(rs1, 5) +
            spec["funct3"] +
            imm[7:] +
            spec["opcode"]
        )

    elif spec["type"] == "R_float":
        # R-type: funct7 | rs2 | rs1 | funct3 | rd | opcode
        rd = register_map[tokens[1]]
        rs1 = register_map[tokens[2]]
        rs2 = register_map[tokens[3]]
        return to_hex(
            spec["funct7"] +
            to_bin(rs2, 5) +
            to_bin(rs1, 5) +
            spec["funct3"] +
            to_bin(rd, 5) +
            spec["opcode"]
        )

    elif spec["type"] == "R_rm_float":
        # R-type with rm field: funct7 | rs2 | rs1 | rm | rd | opcode
        rd = register_map[tokens[1]]
        rs1 = register_map[tokens[2]]
        rs2 = register_map[tokens[3]]
        return to_hex(
            spec["funct7"] +
            to_bin(rs2, 5) +
            to_bin(rs1, 5) +
            rm_bin +
            to_bin(rd, 5) +
            spec["opcode"]
        )

    elif spec["type"] == "SQRT_float":
        rd = register_map[tokens[1]]
        rs1 = register_map[tokens[2]]
        rs2 = 0
        return to_hex(
            spec["funct7"] +
            to_bin(rs2, 5) +
            to_bin(rs1, 5) +
            rm_bin +
            to_bin(rd, 5) +
            spec["opcode"]
        )

    elif spec["type"] == "RCVT_rm_float":
        # Convert operations with rm field: funct7 | rs2 (fixed) | rs1 | rm | rd | opcode
        rd = register_map[tokens[1]]
        rs1 = register_map[tokens[2]]
        rs2 = int(spec["rs2"], 2)
        return to_hex(
            spec["funct7"] +
            to_bin(rs2, 5) +
            to_bin(rs1, 5) +
            rm_bin +
            to_bin(rd, 5) +
            spec["opcode"]
        )

    elif spec["type"] == "RCVT_float":
        # Convert operations without rm field: funct7 | rs2 | rs1 | funct3 | rd | opcode
        rd = register_map[tokens[1]]
        rs1 = register_map[tokens[2]]
        rs2 = int(spec["rs2"], 2)
        return to_hex(
            spec["funct7"] +
            to_bin(rs2, 5) +
            to_bin(rs1, 5) +
            spec["funct3"] +
            to_bin(rd, 5) +
            spec["opcode"]
        )

    elif spec["type"] == "R4_float":
        # Format: rs3 (5) | rs2 (5) | rs1 (5) | rm (3) | rd (5) | opcode (7)
        rd  = register_map[tokens[1]]
        rs1 = register_map[tokens[2]]
        rs2 = register_map[tokens[3]]
        rs3 = register_map[tokens[4]]
        return to_hex(
            to_bin(rs3, 5) +
            spec["funct2"] +
            to_bin(rs2, 5) +
            to_bin(rs1, 5) +
            rm_bin +
            to_bin(rd, 5) +
            spec["opcode"]
        )

    elif spec["type"] == "NOP":
        return to_hex(
            "0" * 25 +
            spec["opcode"]
        )

    else:
        raise ValueError(f"Unsupported instruction format for {mnemonic}\n→ Instruction: {instr}")

def read_instructions_from_file(filename):
    with open(filename, "r") as f:
        # Keep only non-empty, non-comment lines
        return [line.strip() for line in f if line.strip() and not line.startswith("#")]

def write_hex_to_file(hex_list, filename):
    with open(filename, "w") as f:
        for h in hex_list:
            f.write(h + "\n")

def preprocess_asm(input_path, temp_path):
    with open(input_path, 'r') as fin, open(temp_path, 'w') as fout:
        for line in fin:
            line = line.split('#', 1)[0].strip()
            if not line or line.startswith('#'):  # Skip empty or comment lines
                continue
            if ':' in line:
                # Split once to handle possible extra ':' (e.g., comments)
                parts = line.split(':', 1)
                label = parts[0].strip()
                fout.write(f"{label}:\n")
                if len(parts) > 1:
                    instr = parts[1].strip()
                    if instr:
                        fout.write(f"{instr}\n")
            else:
                fout.write(f"{line}\n")

if __name__ == "__main__":
    input_file = "./input_instr.txt"
    temp_file = "./temp_instr.txt"
    output_file = "../mem/ALL_test.mem"

    rm = input("Choose rounding mode (RNE, RTZ, RDN, RUP, RMM, DYN): ").strip().upper()

    if rm not in rounding_mode_map:
        print("Invalid rounding mode!")
        exit(1)

    rm_bin = rounding_mode_map[rm]

    preprocess_asm(input_file, temp_file)

    try:
        raw_lines = read_instructions_from_file(temp_file)
        instructions, label_addr = parse_labels(raw_lines)

        hex_codes = []
        for idx, instr in enumerate(instructions):
            hex_codes.append(encode_instruction(instr, idx, label_addr, rm_bin))

        write_hex_to_file(hex_codes, output_file)
        print(f"Successfully converted {len(hex_codes)} instructions to HEX → {output_file}")
    except Exception as e:
        print("[Error] ===", e)
    
    os.remove(temp_file)
