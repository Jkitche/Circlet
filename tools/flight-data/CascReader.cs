// Circlet tools: reads files from a local World of Warcraft install (CASC storage) and
// decodes DB2 tables (WDC3/WDC4/WDC5). Only what the flight data generator needs:
// local index files -> data archives -> BLTE, the encoding file (content key -> encoded
// key) and the root file (file data ID -> content key). Read-only; touches nothing.
// Compiled by Make-FlightData.ps1 through Add-Type (C# 5, .NET Framework).
using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Text;

namespace CircletTools
{
    public class Casc
    {
        readonly string dataDir; // ...\World of Warcraft\Data
        readonly Dictionary<string, long[]> index = new Dictionary<string, long[]>(); // 9-byte ekey hex -> archive, offset, size
        readonly Dictionary<string, byte[]> rootByFdid = new Dictionary<string, byte[]>();
        byte[] encoding;
        int ceKeySize, cePageSize, cePageCount, cePageIndexStart, cePagesStart;
        public string Log = "";

        public Casc(string wowDir, string product)
        {
            dataDir = Path.Combine(wowDir, "Data");
            string buildKey = BuildKey(Path.Combine(wowDir, ".build.info"), product);
            Log += "build key " + buildKey + "\n";
            var cfg = ReadConfig(buildKey);
            LoadIndexes();
            Log += "index entries " + index.Count + "\n";
            string[] enc = cfg["encoding"].Split(' ');
            encoding = ReadEKey(Hex(enc[1]));
            ParseEncodingHeader();
            byte[] root = ReadCKey(Hex(cfg["root"].Split(' ')[0]));
            ParseRoot(root);
            Log += "root files " + rootByFdid.Count + "\n";
        }

        // ---------------------------------------------------------------- config
        static string BuildKey(string buildInfo, string product)
        {
            string[] lines = File.ReadAllLines(buildInfo);
            string[] head = lines[0].Split('|');
            int keyCol = -1, prodCol = -1;
            for (int i = 0; i < head.Length; i++)
            {
                if (head[i].StartsWith("Build Key")) keyCol = i;
                if (head[i].StartsWith("Product")) prodCol = i;
            }
            for (int l = 1; l < lines.Length; l++)
            {
                string[] f = lines[l].Split('|');
                if (f.Length > Math.Max(keyCol, prodCol) && (prodCol < 0 || f[prodCol] == product)) return f[keyCol];
            }
            throw new Exception("no build for product " + product);
        }

        Dictionary<string, string> ReadConfig(string key)
        {
            string p = Path.Combine(dataDir, "config", key.Substring(0, 2), key.Substring(2, 2), key);
            var d = new Dictionary<string, string>();
            foreach (string line in File.ReadAllLines(p))
            {
                int eq = line.IndexOf(" = ");
                if (eq > 0) d[line.Substring(0, eq).Trim()] = line.Substring(eq + 3).Trim();
            }
            return d;
        }

        // ---------------------------------------------------------------- local indexes
        void LoadIndexes()
        {
            string dir = Path.Combine(dataDir, "data");
            for (int bucket = 0; bucket < 16; bucket++)
            {
                string best = null;
                foreach (string f in Directory.GetFiles(dir, bucket.ToString("x2") + "*.idx"))
                    if (best == null || string.CompareOrdinal(Path.GetFileName(f), Path.GetFileName(best)) > 0) best = f;
                if (best == null) continue;
                using (var br = new BinaryReader(new FileStream(best, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete)))
                {
                    int headerHashSize = br.ReadInt32();
                    br.ReadInt32();
                    br.ReadBytes(headerHashSize);
                    br.BaseStream.Position = (8 + headerHashSize + 0x0F) & ~0x0F;
                    int entriesSize = br.ReadInt32();
                    br.ReadInt32();
                    int n = entriesSize / 18;
                    for (int i = 0; i < n; i++)
                    {
                        byte[] k = br.ReadBytes(9);
                        byte hi = br.ReadByte();
                        byte[] lo = br.ReadBytes(4);
                        uint low = (uint)(lo[0] << 24 | lo[1] << 16 | lo[2] << 8 | lo[3]);
                        int size = br.ReadInt32();
                        long archive = ((long)hi << 2) | (long)((low & 0xC0000000u) >> 30);
                        long offset = low & 0x3FFFFFFF;
                        string key = ToHex(k);
                        if (!index.ContainsKey(key)) index[key] = new long[] { archive, offset, size };
                    }
                }
            }
        }

        public byte[] ReadEKey(byte[] ekey)
        {
            string key = ToHex(ekey, 9);
            long[] e;
            if (!index.TryGetValue(key, out e)) throw new Exception("encoded key not in local storage: " + ToHex(ekey));
            string archive = Path.Combine(dataDir, "data", "data." + e[0].ToString("000"));
            using (var fs = new FileStream(archive, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            {
                fs.Position = e[1] + 30; // skip the 30-byte local header
                byte[] buf = new byte[e[2] - 30];
                int read = 0;
                while (read < buf.Length) { int r = fs.Read(buf, read, buf.Length - read); if (r <= 0) break; read += r; }
                return Blte(buf);
            }
        }

        // ---------------------------------------------------------------- BLTE
        static uint BE32(byte[] b, int o) { return (uint)(b[o] << 24 | b[o + 1] << 16 | b[o + 2] << 8 | b[o + 3]); }

        static byte[] Blte(byte[] b)
        {
            if (b[0] != 'B' || b[1] != 'L' || b[2] != 'T' || b[3] != 'E') throw new Exception("not BLTE");
            int headerSize = (int)BE32(b, 4);
            var outp = new MemoryStream();
            if (headerSize == 0)
            {
                Chunk(b, 8, b.Length - 8, -1, outp);
                return outp.ToArray();
            }
            int count = b[9] << 16 | b[10] << 8 | b[11];
            int pos = headerSize;
            for (int i = 0; i < count; i++)
            {
                int e = 12 + i * 24;
                int comp = (int)BE32(b, e), decomp = (int)BE32(b, e + 4);
                Chunk(b, pos, comp, decomp, outp);
                pos += comp;
            }
            return outp.ToArray();
        }

        static void Chunk(byte[] b, int pos, int len, int decomp, MemoryStream outp)
        {
            char mode = (char)b[pos];
            if (mode == 'N') outp.Write(b, pos + 1, len - 1);
            else if (mode == 'Z')
            {
                // zlib: skip the 2-byte header, the rest is deflate
                using (var ds = new DeflateStream(new MemoryStream(b, pos + 3, len - 3), CompressionMode.Decompress))
                    ds.CopyTo(outp);
            }
            else if (mode == 'F') { byte[] inner = new byte[len - 1]; Array.Copy(b, pos + 1, inner, 0, len - 1); byte[] d = Blte(inner); outp.Write(d, 0, d.Length); }
            else if (mode == 'E') { if (decomp > 0) outp.Write(new byte[decomp], 0, decomp); } // encrypted: left zeroed
            else throw new Exception("unknown BLTE chunk mode " + mode);
        }

        // ---------------------------------------------------------------- encoding
        void ParseEncodingHeader()
        {
            byte[] b = encoding;
            if (b[0] != 'E' || b[1] != 'N') throw new Exception("bad encoding file");
            ceKeySize = b[3];
            cePageSize = (b[5] << 8 | b[6]) * 1024;
            cePageCount = (int)BE32(b, 9);
            int especBlock = (int)BE32(b, 18);
            cePageIndexStart = 22 + especBlock;
            cePagesStart = cePageIndexStart + cePageCount * (ceKeySize + 16);
        }

        static int Compare(byte[] a, int ao, byte[] b, int bo, int n)
        {
            for (int i = 0; i < n; i++) { int d = a[ao + i] - b[bo + i]; if (d != 0) return d; }
            return 0;
        }

        public byte[] EKeyFor(byte[] ckey)
        {
            byte[] b = encoding;
            int lo = 0, hi = cePageCount - 1, page = 0;
            while (lo <= hi)
            {
                int mid = (lo + hi) / 2;
                if (Compare(b, cePageIndexStart + mid * (ceKeySize + 16), ckey, 0, ceKeySize) <= 0) { page = mid; lo = mid + 1; }
                else hi = mid - 1;
            }
            int p = cePagesStart + page * cePageSize, end = p + cePageSize;
            while (p < end)
            {
                int keys = b[p];
                if (keys == 0) break;
                int ck = p + 6;
                if (Compare(b, ck, ckey, 0, ceKeySize) == 0)
                {
                    byte[] ek = new byte[16];
                    Array.Copy(b, ck + ceKeySize, ek, 0, 16);
                    return ek;
                }
                p = ck + ceKeySize + keys * 16;
            }
            throw new Exception("content key not in encoding file: " + ToHex(ckey));
        }

        public byte[] ReadCKey(byte[] ckey) { return ReadEKey(EKeyFor(ckey)); }

        // ---------------------------------------------------------------- root
        void ParseRoot(byte[] b)
        {
            var br = new BinaryReader(new MemoryStream(b));
            uint magic = br.ReadUInt32();
            if (magic != 0x4D465354) throw new Exception("unsupported root format");
            uint headerSize = br.ReadUInt32(), version = br.ReadUInt32();
            uint total, named;
            if (headerSize > 1000) { total = headerSize; named = version; headerSize = 12; version = 0; }
            else { total = br.ReadUInt32(); named = br.ReadUInt32(); }
            br.BaseStream.Position = headerSize;
            bool allowNoNames = total != named;
            while (br.BaseStream.Position < b.Length)
            {
                int count = br.ReadInt32();
                uint contentFlags, localeFlags;
                if (version >= 2)
                {
                    localeFlags = br.ReadUInt32();
                    uint u1 = br.ReadUInt32(), u2 = br.ReadUInt32();
                    byte u3 = br.ReadByte();
                    contentFlags = u1 | u2 | ((uint)u3 << 17);
                }
                else { contentFlags = br.ReadUInt32(); localeFlags = br.ReadUInt32(); }
                int[] fdids = new int[count];
                int fd = -1;
                for (int i = 0; i < count; i++) { fd = fd + 1 + br.ReadInt32(); fdids[i] = fd; }
                bool enUS = (localeFlags & 0x2) != 0 || localeFlags == 0xFFFFFFFF;
                for (int i = 0; i < count; i++)
                {
                    byte[] ck = br.ReadBytes(16);
                    string k = fdids[i].ToString();
                    if (enUS || !rootByFdid.ContainsKey(k)) { if (enUS || !rootByFdid.ContainsKey(k)) rootByFdid[k] = ck; }
                }
                bool noNames = (contentFlags & 0x10000000) != 0;
                if (!(allowNoNames && noNames)) br.BaseStream.Position += 8L * count;
            }
        }

        // File data IDs in [lo, hi] that are stored locally and at most maxBytes (encoded).
        public List<int> LocalFiles(int lo, int hi, long maxBytes)
        {
            var list = new List<int>();
            foreach (var kv in rootByFdid)
            {
                int id = int.Parse(kv.Key);
                if (id < lo || id > hi) continue;
                try
                {
                    byte[] ek = EKeyFor(kv.Value);
                    long[] e;
                    if (index.TryGetValue(ToHex(ek, 9), out e) && e[2] <= maxBytes) list.Add(id);
                }
                catch (Exception) { }
            }
            list.Sort();
            return list;
        }

        public byte[] ReadFileDataID(int fdid)
        {
            byte[] ck;
            if (!rootByFdid.TryGetValue(fdid.ToString(), out ck)) throw new Exception("file data ID not in root: " + fdid);
            return ReadCKey(ck);
        }

        // ---------------------------------------------------------------- hex
        public static byte[] Hex(string s)
        {
            byte[] r = new byte[s.Length / 2];
            for (int i = 0; i < r.Length; i++) r[i] = Convert.ToByte(s.Substring(i * 2, 2), 16);
            return r;
        }
        static string ToHex(byte[] b) { return ToHex(b, b.Length); }
        static string ToHex(byte[] b, int n)
        {
            var sb = new StringBuilder(n * 2);
            for (int i = 0; i < n; i++) sb.Append(b[i].ToString("x2"));
            return sb.ToString();
        }
    }

    // One decoded DB2 record: its ID, the parent ID from the relationship data (if any),
    // and every field as raw 32-bit values (an array field has several).
    public class Db2Record
    {
        public int ID;
        public int Parent;
        public uint[][] Fields;
        public int GlobalIndex; // for resolving string offsets
    }

    public class Db2
    {
        public string Magic;
        public int FieldCount, RecordSize;
        public uint Flags;
        public int IdIndex;
        public List<Db2Record> Records = new List<Db2Record>();
        public string Info = "";
        byte[] data;
        int[] fOffBits, fSizeBits, fType, fV1, fV2, fV3, fAdd;
        int[] palletStart;
        Dictionary<int, uint>[] common;
        byte[] pallet;
        // strings: virtual layout = every section's records, then every section's string table
        long totalRecordBytes;
        readonly Dictionary<long, string> strings = new Dictionary<long, string>();

        public Db2(byte[] b)
        {
            data = b;
            var br = new BinaryReader(new MemoryStream(b));
            Magic = Encoding.ASCII.GetString(br.ReadBytes(4));
            if (Magic == "WDC5") { br.ReadUInt32(); br.ReadBytes(128); }
            else if (Magic != "WDC4" && Magic != "WDC3") throw new Exception("unsupported DB2 " + Magic);
            int recordCount = br.ReadInt32();
            FieldCount = br.ReadInt32();
            RecordSize = br.ReadInt32();
            br.ReadInt32(); // string table size
            br.ReadUInt32(); br.ReadUInt32(); // table / layout hash
            br.ReadInt32(); br.ReadInt32(); br.ReadInt32(); // min id, max id, locale
            Flags = br.ReadUInt16();
            IdIndex = br.ReadUInt16();
            br.ReadInt32(); br.ReadInt32(); br.ReadInt32(); // total field count, bitpacked offset, lookup columns
            int storageSize = br.ReadInt32(), commonSize = br.ReadInt32(), palletSize = br.ReadInt32();
            int sectionCount = br.ReadInt32();
            Info = Magic + " records " + recordCount + " fields " + FieldCount + " recordSize " + RecordSize + " flags " + Flags + " idIndex " + IdIndex + " sections " + sectionCount;
            var sec = new long[sectionCount][];
            for (int i = 0; i < sectionCount; i++)
            {
                ulong tact = br.ReadUInt64();
                sec[i] = new long[] { br.ReadInt32(), br.ReadInt32(), br.ReadInt32(), br.ReadInt32(), br.ReadInt32(), br.ReadInt32(), br.ReadInt32(), br.ReadInt32(), (long)(tact != 0 ? 1 : 0) };
                // fileOffset, recordCount, stringTableSize, offsetRecordsEnd, idListSize, relationshipSize, offsetMapIdCount, copyTableCount, encrypted
            }
            br.BaseStream.Position += 4L * FieldCount; // field structure (size, position)
            int n = storageSize / 24;
            fOffBits = new int[n]; fSizeBits = new int[n]; fType = new int[n]; fV1 = new int[n]; fV2 = new int[n]; fV3 = new int[n]; fAdd = new int[n];
            for (int i = 0; i < n; i++)
            {
                fOffBits[i] = br.ReadUInt16(); fSizeBits[i] = br.ReadUInt16(); fAdd[i] = br.ReadInt32();
                fType[i] = br.ReadInt32(); fV1[i] = br.ReadInt32(); fV2[i] = br.ReadInt32(); fV3[i] = br.ReadInt32();
                Info += "\n  field " + i + ": bits " + fOffBits[i] + "+" + fSizeBits[i] + " type " + fType[i] + " v " + fV1[i] + "," + fV2[i] + "," + fV3[i] + " add " + fAdd[i];
            }
            pallet = br.ReadBytes(palletSize);
            palletStart = new int[n];
            int pp = 0;
            for (int i = 0; i < n; i++) if (fType[i] == 3 || fType[i] == 4) { palletStart[i] = pp; pp += fAdd[i]; }
            common = new Dictionary<int, uint>[n];
            for (int i = 0; i < n; i++)
            {
                if (fType[i] != 2) continue;
                common[i] = new Dictionary<int, uint>();
                for (int k = 0; k < fAdd[i] / 8; k++) common[i][br.ReadInt32()] = br.ReadUInt32();
            }
            if ((Flags & 1) != 0) throw new Exception("sparse DB2 not supported");

            for (int s = 0; s < sectionCount; s++) totalRecordBytes += sec[s][1] * RecordSize;
            long strBefore = 0;
            int globalIndex = 0;
            for (int s = 0; s < sectionCount; s++)
            {
                long off = sec[s][0];
                int count = (int)sec[s][1];
                int strSize = (int)sec[s][2];
                long recStart = off;
                long strStart = off + (long)count * RecordSize;
                // strings
                long p = strStart;
                while (p < strStart + strSize)
                {
                    long q = p;
                    while (q < strStart + strSize && b[q] != 0) q++;
                    strings[totalRecordBytes + strBefore + (p - strStart)] = Encoding.UTF8.GetString(b, (int)p, (int)(q - p));
                    p = q + 1;
                }
                br.BaseStream.Position = strStart + strSize;
                int[] ids = new int[sec[s][4] / 4];
                for (int i = 0; i < ids.Length; i++) ids[i] = br.ReadInt32();
                var copies = new List<int[]>();
                for (int i = 0; i < sec[s][7]; i++) copies.Add(new int[] { br.ReadInt32(), br.ReadInt32() });
                var parent = new Dictionary<int, int>();
                if (sec[s][5] > 0)
                {
                    int entries = br.ReadInt32();
                    br.ReadInt32(); br.ReadInt32();
                    for (int i = 0; i < entries; i++) { int foreign = br.ReadInt32(); int ri = br.ReadInt32(); parent[ri] = foreign; }
                }
                bool zeroed = sec[s][8] == 1 && IsZero(b, recStart, count * RecordSize);
                var byId = new Dictionary<int, Db2Record>();
                for (int r = 0; r < count; r++)
                {
                    var rec = new Db2Record();
                    rec.GlobalIndex = globalIndex++;
                    long ro = recStart + (long)r * RecordSize;
                    rec.Fields = new uint[n][];
                    for (int f = 0; f < n; f++) rec.Fields[f] = Field(ro, f, ids.Length > 0 ? ids[r] : -1);
                    rec.ID = ids.Length > 0 ? ids[r] : (int)rec.Fields[IdIndex][0];
                    if (ids.Length == 0 && common[IdIndex] == null) rec.ID = (int)rec.Fields[IdIndex][0];
                    int par;
                    rec.Parent = parent.TryGetValue(r, out par) ? par : 0;
                    if (zeroed) continue; // encrypted section we can't read
                    Records.Add(rec);
                    byId[rec.ID] = rec;
                }
                foreach (int[] c in copies)
                {
                    Db2Record src;
                    if (!byId.TryGetValue(c[1], out src)) continue;
                    var rec = new Db2Record { ID = c[0], Parent = src.Parent, Fields = src.Fields, GlobalIndex = src.GlobalIndex };
                    Records.Add(rec);
                }
                strBefore += strSize;
            }
        }

        static bool IsZero(byte[] b, long start, int len)
        {
            for (long i = start; i < start + len && i < b.Length; i++) if (b[i] != 0) return false;
            return true;
        }

        ulong Bits(long recordOffset, int bitOffset, int bitCount)
        {
            ulong v = 0;
            for (int i = 0; i < bitCount; i++)
            {
                int bit = bitOffset + i;
                if ((data[recordOffset + (bit >> 3)] >> (bit & 7) & 1) != 0) v |= 1UL << i;
            }
            return v;
        }

        uint[] Field(long ro, int f, int id)
        {
            switch (fType[f])
            {
                case 0: // inline: possibly an array of 32-bit (or a single smaller) value(s)
                    {
                        int bytes = fSizeBits[f] / 8, start = fOffBits[f] / 8;
                        if (bytes <= 4) return new uint[] { (uint)Bits(ro, fOffBits[f], fSizeBits[f]) };
                        uint[] a = new uint[bytes / 4];
                        for (int i = 0; i < a.Length; i++) a[i] = BitConverter.ToUInt32(data, (int)(ro + start + i * 4));
                        return a;
                    }
                case 1:
                case 5:
                    {
                        ulong v = Bits(ro, fOffBits[f], fV2[f]);
                        if (fType[f] == 5 && fV2[f] < 32 && (v & (1UL << (fV2[f] - 1))) != 0) v |= ~((1UL << fV2[f]) - 1);
                        return new uint[] { (uint)v };
                    }
                case 2:
                    {
                        uint v;
                        if (id >= 0 && common[f].TryGetValue(id, out v)) return new uint[] { v };
                        return new uint[] { (uint)fV1[f] };
                    }
                case 3:
                    {
                        int idx = (int)Bits(ro, fOffBits[f], fV2[f]);
                        return new uint[] { BitConverter.ToUInt32(pallet, palletStart[f] + idx * 4) };
                    }
                case 4:
                    {
                        int idx = (int)Bits(ro, fOffBits[f], fV2[f]), cnt = fV3[f];
                        uint[] a = new uint[cnt];
                        for (int i = 0; i < cnt; i++) a[i] = BitConverter.ToUInt32(pallet, palletStart[f] + (idx * cnt + i) * 4);
                        return a;
                    }
            }
            return new uint[] { 0 };
        }

        // A string field's text, from its raw offset value.
        public string String(Db2Record rec, int f)
        {
            long pos = (long)rec.GlobalIndex * RecordSize + fOffBits[f] / 8 + rec.Fields[f][0];
            string s;
            return strings.TryGetValue(pos, out s) ? s : null;
        }

        public static float F(uint v) { return BitConverter.ToSingle(BitConverter.GetBytes(v), 0); }
    }
}
