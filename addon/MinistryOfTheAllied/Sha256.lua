-- Ministry of the Allied: SHA-256 (FIPS 180-4), for the lottery's draw.
-- Written with plain arithmetic rather than the game's bit library, so every
-- copy (and the test client) gets exactly the same answer.
--
--   MOTA.Sha256(text)  ->  64 lowercase hex digits

local _, MOTA = ...

local MOD = 4294967296 -- 2^32
local floor = math.floor

-- AND and XOR of two 4-bit numbers, looked up; 32-bit ones a nibble at a time.
local AND4, XOR4 = {}, {}
for a = 0, 15 do
  for b = 0, 15 do
    local r_and, r_xor, bit = 0, 0, 1
    local x, y = a, b
    for _ = 1, 4 do
      local xa, yb = x % 2, y % 2
      if xa == 1 and yb == 1 then r_and = r_and + bit end
      if xa ~= yb then r_xor = r_xor + bit end
      x, y, bit = floor(x / 2), floor(y / 2), bit * 2
    end
    AND4[a * 16 + b], XOR4[a * 16 + b] = r_and, r_xor
  end
end

local function op(t, a, b)
  local r, m = 0, 1
  for _ = 1, 8 do
    r = r + t[(a % 16) * 16 + (b % 16)] * m
    a, b, m = floor(a / 16), floor(b / 16), m * 16
  end
  return r
end
local function band(a, b) return op(AND4, a, b) end
local function bxor(a, b) return op(XOR4, a, b) end
local function bnot(a) return MOD - 1 - a end
local function shr(a, n) return floor(a / 2 ^ n) end
local function rotr(a, n)
  local p = 2 ^ n
  return floor(a / p) + (a % p) * (MOD / p)
end

local K = {
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}
local H0 = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }

local function digest(msg)
  -- Pad: a 1 bit, zeros, then the length in bits as 8 bytes, to a multiple of 64 bytes.
  local len = #msg
  local bits = len * 8
  local tail = { "\128", string.rep("\0", (55 - len) % 64) }
  local lenBytes = {}
  for i = 8, 1, -1 do
    lenBytes[i] = string.char(bits % 256)
    bits = floor(bits / 256)
  end
  msg = msg .. table.concat(tail) .. table.concat(lenBytes)

  local H = { unpack(H0) }
  local w = {}
  for chunk = 1, #msg, 64 do
    for i = 0, 15 do
      local b1, b2, b3, b4 = msg:byte(chunk + i * 4, chunk + i * 4 + 3)
      w[i] = ((b1 * 256 + b2) * 256 + b3) * 256 + b4
    end
    for i = 16, 63 do
      local s0 = bxor(bxor(rotr(w[i - 15], 7), rotr(w[i - 15], 18)), shr(w[i - 15], 3))
      local s1 = bxor(bxor(rotr(w[i - 2], 17), rotr(w[i - 2], 19)), shr(w[i - 2], 10))
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) % MOD
    end
    local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
    for i = 0, 63 do
      local S1 = bxor(bxor(rotr(e, 6), rotr(e, 11)), rotr(e, 25))
      local ch = bxor(band(e, f), band(bnot(e), g))
      local t1 = (h + S1 + ch + K[i + 1] + w[i]) % MOD
      local S0 = bxor(bxor(rotr(a, 2), rotr(a, 13)), rotr(a, 22))
      local maj = bxor(bxor(band(a, b), band(a, c)), band(b, c))
      local t2 = (S0 + maj) % MOD
      h, g, f, e, d, c, b, a = g, f, e, (d + t1) % MOD, c, b, a, (t1 + t2) % MOD
    end
    H[1], H[2], H[3], H[4] = (H[1] + a) % MOD, (H[2] + b) % MOD, (H[3] + c) % MOD, (H[4] + d) % MOD
    H[5], H[6], H[7], H[8] = (H[5] + e) % MOD, (H[6] + f) % MOD, (H[7] + g) % MOD, (H[8] + h) % MOD
  end
  local out = {}
  for i = 1, 8 do out[i] = string.format("%08x", H[i]) end
  return table.concat(out)
end

MOTA.Sha256 = digest

-- XOR of two bytes (0-255), for the treasure hunt's sealed riddles.
function MOTA.ByteXor(a, b)
  return XOR4[floor(a / 16) * 16 + floor(b / 16)] * 16 + XOR4[(a % 16) * 16 + (b % 16)]
end
