// SharpProspero - a C# SDK for on-device application modules.
// Copyright (C) 2026 SvenGDK

using SharpProspero.Interop;
using System;
using System.Collections.Generic;
using System.Text;

namespace SharpProspero.Storage;

/// <summary>One member of a tar archive: its path, whether it is a directory, and its bytes.</summary>
/// <param name="Name">The stored path, with a directory prefix already joined on.</param>
/// <param name="IsDirectory">True for a directory entry, which carries no data.</param>
/// <param name="Data">The file's bytes, or an empty array for a directory.</param>
public readonly record struct TarEntry(string Name, bool IsDirectory, byte[] Data)
{
    /// <summary>The entry's bytes decoded as UTF-8 text.</summary>
    public string Text => Encoding.UTF8.GetString(Data);
}

/// <summary>
/// Reads a tar archive — the common way to bundle many asset files into one — into its members, with no
/// system module. It understands the widely used forms (the original layout, the ustar extension with its
/// long-path prefix, and GNU long names) and returns regular files and directories; other record kinds,
/// such as links and device nodes, are skipped. The archive is not compressed, so a member's bytes are
/// returned as they are stored.
/// </summary>
/// <example>
/// <code>
/// foreach (TarEntry entry in TarArchive.Read(FileSystem.ReadAllBytes("/data/assets.tar")))
/// {
///     if (!entry.IsDirectory)
///         Install(entry.Name, entry.Data);
/// }
/// </code>
/// </example>
public static class TarArchive
{
    private const int BlockSize = 512;

    /// <summary>Reads <paramref name="data"/> and returns its regular-file and directory members in order.</summary>
    /// <exception cref="ProsperoException">The archive is malformed — a bad header checksum, a bad size, or an entry running past the end.</exception>
    public static List<TarEntry> Read(ReadOnlySpan<byte> data)
    {
        var entries = new List<TarEntry>();
        string? longName = null;
        // A name and a length carried by an extended header for the entry that follows it. They take
        // precedence over the older long-name record and over the header's own fields, which is what
        // the writer that emits them relies on: it leaves a shortened name in the header for a reader
        // that does not understand the extended one.
        string? extendedName = null;
        long? extendedSize = null;
        int offset = 0;

        while (offset + BlockSize <= data.Length)
        {
            ReadOnlySpan<byte> header = data.Slice(offset, BlockSize);
            if (IsZeroBlock(header))
                break; // two zero blocks end the archive; the first is enough to stop.

            if (!ChecksumMatches(header))
                throw new ProsperoException("The tar header checksum does not match.", -1);

            long size = ParseOctal(header.Slice(124, 12));
            if (size < 0)
                throw new ProsperoException("The tar entry has an invalid size.", -1);

            byte typeFlag = header[156];
            offset += BlockSize;
            if (offset + size > data.Length)
                throw new ProsperoException("The tar entry runs past the end of the archive.", -1);

            int dataLength = (int)size;               // safe: size <= data.Length - offset, an int range.
            int paddedLength = RoundUpToBlock(dataLength);

            switch (typeFlag)
            {
                case (byte)'L': // A GNU long-name record: its data is the next entry's full path.
                    string parsed = ReadString(data.Slice(offset, dataLength));
                    longName = parsed.Length > 0 ? parsed : null; // an empty payload falls back to the header name
                    break;

                case (byte)'x': // An extended header for the entry that follows it.
                    ReadExtendedHeader(data.Slice(offset, dataLength), ref extendedName, ref extendedSize);
                    break;

                case (byte)'g': // The same, for every entry that follows. Read so it cannot be
                    {           // mistaken for the next entry's own, and then set aside.
                        string? ignoredName = null;
                        long? ignoredSize = null;
                        ReadExtendedHeader(data.Slice(offset, dataLength), ref ignoredName, ref ignoredSize);
                        break;
                    }

                case 0:
                case (byte)'0':
                case (byte)'7': // A regular (or contiguous) file.
                    {
                        string name = extendedName ?? longName ?? ReadName(header);
                        longName = null;
                        extendedName = null;
                        if (extendedSize is long carried)
                        {
                            if (carried < 0 || carried > data.Length - offset)
                                throw new ProsperoException("The tar entry runs past the end of the archive.", -1);
                            dataLength = (int)carried;
                            paddedLength = RoundUpToBlock(dataLength);
                            extendedSize = null;
                        }
                        bool trailingSlash = name.Length > 0 && name[^1] == '/';
                        entries.Add(new TarEntry(name, trailingSlash, trailingSlash ? [] : data.Slice(offset, dataLength).ToArray()));
                        break;
                    }

                case (byte)'5': // A directory.
                    {
                        string name = extendedName ?? longName ?? ReadName(header);
                        longName = null;
                        extendedName = null;
                        extendedSize = null;
                        entries.Add(new TarEntry(name, true, []));
                        break;
                    }

                default: // Links and device nodes are skipped, but any name held for the next entry is spent.
                    longName = null;
                    extendedName = null;
                    extendedSize = null;
                    break;
            }

            // The trailing padding of the last entry may be absent from a truncated archive; when it runs
            // off the end there are no further blocks, so stop rather than advance past the buffer.
            if (paddedLength > data.Length - offset)
                break;
            offset += paddedLength;
        }

        return entries;
    }

    // An extended header holds a run of records, each "<length> <key>=<value>\n" where the length
    // counts the whole record including itself and the newline. Only two keys change what the entry
    // is: the path, which is how a name longer than the header's field is carried, and the size, which
    // is how a length the header's octal field cannot hold is carried. A record that cannot be read
    // ends the run rather than being guessed at.
    private static void ReadExtendedHeader(ReadOnlySpan<byte> payload, ref string? name, ref long? size)
    {
        int at = 0;
        while (at < payload.Length)
        {
            int space = payload[at..].IndexOf((byte)' ');
            if (space <= 0)
                return;
            if (!int.TryParse(Encoding.ASCII.GetString(payload.Slice(at, space)), out int length)
                || length <= space + 1 || length > payload.Length - at)
                return;
            ReadOnlySpan<byte> record = payload.Slice(at + space + 1, length - space - 2);
            at += length;

            int equals = record.IndexOf((byte)'=');
            if (equals <= 0)
                continue;
            string key = Encoding.ASCII.GetString(record[..equals]);
            ReadOnlySpan<byte> value = record[(equals + 1)..];
            if (key == "path")
                name = Encoding.UTF8.GetString(value);
            else if (key == "size" && long.TryParse(Encoding.ASCII.GetString(value), out long parsed))
                size = parsed;
        }
    }

    private static string ReadName(ReadOnlySpan<byte> header)
    {
        string name = ReadString(header[..100]);

        // One layout splits a long path into a 155-byte prefix and the 100-byte name. Another writes
        // the same five letters in that field and puts three timestamps where the prefix would be, so
        // comparing only the letters read those timestamps as a directory and put one in front of
        // every name. The character after the letters is what separates the two.
        if (header.Slice(257, 6).SequenceEqual("ustar "u8))
        {
            string prefix = ReadString(header.Slice(345, 155));
            if (prefix.Length > 0)
                return prefix + "/" + name;
        }

        return name;
    }

    private static string ReadString(ReadOnlySpan<byte> field)
    {
        int end = field.IndexOf((byte)0);
        if (end < 0)
            end = field.Length;
        return Encoding.UTF8.GetString(field[..end]);
    }

    private static long ParseOctal(ReadOnlySpan<byte> field)
    {
        int start = 0;
        int end = field.Length;
        while (start < end && (field[start] == ' ' || field[start] == 0))
            start++;
        while (end > start && (field[end - 1] == ' ' || field[end - 1] == 0))
            end--;

        long value = 0;
        for (int i = start; i < end; i++)
        {
            byte b = field[i];
            if (b < '0' || b > '7')
                return -1;
            value = (value << 3) + (b - '0');
        }

        return value;
    }

    private static bool ChecksumMatches(ReadOnlySpan<byte> header)
    {
        long stored = ParseOctal(header.Slice(148, 8));
        if (stored < 0)
            return false;

        // The checksum is computed with its own eight-byte field read as spaces. Accept the unsigned sum
        // and the signed sum, since old archives used one or the other.
        long unsignedSum = 0;
        long signedSum = 0;
        for (int i = 0; i < BlockSize; i++)
        {
            int b = (i >= 148 && i < 156) ? ' ' : header[i];
            unsignedSum += b;
            signedSum += (sbyte)b;
        }

        return stored == unsignedSum || stored == signedSum;
    }

    private static bool IsZeroBlock(ReadOnlySpan<byte> block)
    {
        foreach (byte b in block)
        {
            if (b != 0)
                return false;
        }

        return true;
    }

    private static int RoundUpToBlock(int length) => (length + BlockSize - 1) / BlockSize * BlockSize;
}
