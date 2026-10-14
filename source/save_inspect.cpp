// SPDX-License-Identifier: GPL-2.0-only
// Read-only metadata reader for modern OpenTTD/JGRPP saves.
#include <zlib.h>
#include <lzma.h>
#include <array>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>
#include <cstdint>
#include <algorithm>

using Bytes = std::vector<uint8_t>;
static constexpr size_t LIMIT = 512ULL * 1024 * 1024;
static Bytes decompress(const Bytes &raw)
{
    if (raw.size() < 8) throw std::runtime_error("Not an OpenTTD save: header is missing.");
    std::string tag(raw.begin(), raw.begin() + 4);
    if (tag == "OTTN") return Bytes(raw.begin() + 8, raw.end());
    if (tag != "OTTZ" && tag != "OTTX") throw std::runtime_error("This reader supports zlib, LZMA/XZ and uncompressed saves. Load this save in compatible JGRPP and save a zlib copy first.");
    Bytes out;
    std::array<uint8_t, 65536> block;
    if (tag == "OTTZ") {
        z_stream zs{};
        if (inflateInit(&zs) != Z_OK) throw std::runtime_error("Cannot initialize zlib.");
        zs.next_in = const_cast<uint8_t *>(raw.data() + 8);
        zs.avail_in = static_cast<uInt>(raw.size() - 8);
        int status;
        do {
            zs.next_out = block.data(); zs.avail_out = block.size();
            status = inflate(&zs, Z_NO_FLUSH);
            if (status != Z_OK && status != Z_STREAM_END) { inflateEnd(&zs); throw std::runtime_error("Damaged or truncated zlib save."); }
            size_t count = block.size() - zs.avail_out;
            if (out.size() + count > LIMIT) { inflateEnd(&zs); throw std::runtime_error("Save exceeds the reader's 512 MiB decompressed limit."); }
            out.insert(out.end(), block.begin(), block.begin() + count);
        } while (status != Z_STREAM_END);
        inflateEnd(&zs);
    } else {
        lzma_stream ls = LZMA_STREAM_INIT;
        if (lzma_auto_decoder(&ls, LIMIT, 0) != LZMA_OK) throw std::runtime_error("Cannot initialize LZMA.");
        ls.next_in = raw.data() + 8; ls.avail_in = raw.size() - 8;
        lzma_ret status;
        do {
            ls.next_out = block.data(); ls.avail_out = block.size();
            status = lzma_code(&ls, LZMA_FINISH);
            if (status != LZMA_OK && status != LZMA_STREAM_END) { lzma_end(&ls); throw std::runtime_error("Damaged, truncated or excessively large LZMA save."); }
            size_t count = block.size() - ls.avail_out;
            if (out.size() + count > LIMIT) { lzma_end(&ls); throw std::runtime_error("Save exceeds the reader's 512 MiB decompressed limit."); }
            out.insert(out.end(), block.begin(), block.begin() + count);
        } while (status != LZMA_STREAM_END);
        lzma_end(&ls);
    }
    return out;
}

struct Reader {
    const Bytes &data; size_t pos = 0;
    void check(size_t n) const { if (n > data.size() - pos) throw std::runtime_error("Truncated save chunk."); }
    uint8_t byte() { check(1); return data[pos++]; }
    uint32_t uint32() { uint32_t n = 0; for (int i = 0; i < 4; ++i) n = (n << 8) | byte(); return n; }
    uint32_t gamma() {
        uint8_t b = byte(); unsigned extra = 0;
        while (extra < 8 && (b & (0x80 >> extra))) ++extra;
        if (extra > 4) throw std::runtime_error("Unsupported array length.");
        uint32_t n = b & (0x7f >> extra);
        for (unsigned i = 0; i < extra; ++i) n = (n << 8) | byte();
        return n;
    }
    std::string str(size_t n) { check(n); std::string s(data.begin()+pos, data.begin()+pos+n); pos += n; return s; }
    void skip(size_t n) { check(n); pos += n; }
};
struct Metadata { uint32_t width = 0, height = 0, towns = 0, industries = 0; };
static bool power2(uint32_t v) { return v >= 64 && (v & (v - 1)) == 0; }
static Metadata inspect(const Bytes &data)
{
    Reader r{data}; Metadata m; bool maps = false;
    while (true) {
        uint32_t id = r.uint32(); if (id == 0) break;
        uint8_t mode = r.byte(); uint32_t flags = 0;
        if ((mode & 15) == 15) { flags = r.uint32(); mode = r.byte(); }
        const bool map = id == 0x4d415053, town = id == 0x43495459, industry = id == 0x494e4459;
        if ((mode & 15) == 0) {
            uint64_t length = uint64_t(mode >> 4) << 24;
            for (int i = 2; i >= 0; --i) length |= uint64_t(r.byte()) << (8 * i);
            if (flags & ~uint32_t(1)) throw std::runtime_error("Unsupported extended chunk header.");
            if (flags & 1) length |= uint64_t(r.uint32()) << 28;
            r.check(length);
            if (map) {
                if (length != 8 || maps) throw std::runtime_error("Unsupported MAPS dimensions.");
                m.width = r.uint32(); m.height = r.uint32(); maps = true;
            } else r.skip(length);
        } else {
            if (mode < 1 || mode > 4 || flags != 0) throw std::runtime_error("Unsupported save chunk layout.");
            bool header = mode == 3 || mode == 4;
            std::vector<std::string> fields;
            while (true) {
                uint32_t length = r.gamma(); if (length == 0) break;
                --length; r.check(length); size_t end = r.pos + length;
                if (header) {
                    if (map) {
                        while (r.pos < end) {
                            uint8_t type = r.byte(); if (type == 0) break;
                            if (type != 6) throw std::runtime_error("Unsupported map dimension field.");
                            fields.push_back(r.str(r.gamma()));
                        }
                        if (r.pos != end) throw std::runtime_error("Invalid MAPS header.");
                    }
                    header = false;
                } else {
                    if (mode == 2 || mode == 4) r.gamma();
                    if (r.pos > end) throw std::runtime_error("Invalid sparse array.");
                    if (map && r.pos != end) {
                        if (maps || end - r.pos != 4 * fields.size()) throw std::runtime_error("Unsupported MAPS table.");
                        for (const auto &field : fields) {
                            uint32_t v = r.uint32();
                            if (field == "dim_x") m.width = v;
                            else if (field == "dim_y") m.height = v;
                        }
                        maps = true;
                    } else if (r.pos != end) {
                        if (town) ++m.towns;
                        if (industry) ++m.industries;
                    }
                }
                if (r.pos > end) throw std::runtime_error("Invalid chunk length.");
                r.pos = end;
            }
        }
    }
    if (r.pos != data.size() || !maps || !power2(m.width) || !power2(m.height) || uint64_t(m.width) * m.height > (1ULL << 28)) throw std::runtime_error("Save dimensions or chunk structure are unsupported or corrupt.");
    return m;
}
static int run(const std::filesystem::path &path)
{
    try {
        std::ifstream file(path, std::ios::binary | std::ios::ate);
        if (!file) throw std::runtime_error("Cannot open selected save.");
        auto size = file.tellg();
        if (size < 8 || uint64_t(size) > LIMIT) throw std::runtime_error("Invalid save size (maximum 512 MiB).");
        Bytes raw(static_cast<size_t>(size)); file.seekg(0); file.read(reinterpret_cast<char *>(raw.data()), raw.size());
        if (!file) throw std::runtime_error("Could not read the complete save.");
        Metadata m = inspect(decompress(raw));
        std::cout << "{\"width\":" << m.width << ",\"height\":" << m.height << ",\"towns\":" << m.towns << ",\"industries\":" << m.industries << "}\n";
        return 0;
    } catch (const std::exception &e) { std::cerr << e.what() << '\n'; return 1; }
}
#ifdef _WIN32
int wmain(int argc, wchar_t **argv) { if (argc != 2) return 2; return run(std::filesystem::path(argv[1])); }
#else
int main(int argc, char **argv) { if (argc != 2) return 2; return run(std::filesystem::path(argv[1])); }
#endif
