-- verifier v0.1.0
-- Copyright (C) 2026 Nikita Podvirnyi <krypt0nn@vk.com>
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the “Software”), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.

type Args = {
    path: string,
    size: number?,

    -- "[format]:[base32]" or just "[base32]" for blake3.
    hash: string?
}

type Promise<T> = any

local __cache = {}

return function(args: Args): Promise<boolean>
    local result = nil

    local timestamp = nil
    local hash_future = nil

    return task.create(function(): (boolean, boolean?)
        -- If promise already finished.
        if result ~= nil then
            return true, result
        end

        -- If we're calculating file hash already then try to poll the result.
        if hash_future then
            local status, file_hash = hash_future:poll()

            -- If hash is not calculated yet then keep waiting.
            if not status then
                return false, nil
            end

            -- Otherwise compare hashes and return the result.
            result = str.encode("base32", file_hash) == args.hash

            __cache[args.path] = {
                timestamp = timestamp,
                size = args.size,
                hash = args.hash,
                result = result
            }

            return true, result
        end

        -- If no args or path provided then mark the file as invalid.
        if not args or not args.path or not fs.exists(args.path) then
            result = false

            return true, result
        end

        -- If we don't have any info to compare given file against - just mark the
        -- file as valid.
        if not args.size and not args.hash then
            result = true

            return true, result
        end

        -- Obtain file metadata.
        local metadata = fs.metadata(args.path)

        -- Take either file modification or creation time.
        timestamp = metadata.modified_at or metadata.created_at

        -- If we have cached verification result for this file then return it.
        if __cache[args.path]
            and __cache[args.path].timestamp == timestamp
            and __cache[args.path].size == args.size
            and __cache[args.path].hash == args.hash
        then
            result = __cache[args.path].result

            return true, result
        end

        -- If expected size provided and the file didn't match then mark the
        -- file as invalid.
        if args.size and metadata.length ~= args.size then
            result = false

            __cache[args.path] = {
                timestamp = timestamp,
                size = args.size,
                hash = args.hash,
                result = result
            }

            return true, result
        end

        -- If expected hash provided then start hash calculation task.
        if args.hash and not hash_future then
            local hash_algorithm = "blake3"

            -- Try to find ":" in "[hash]:[base32]" string.
            local algorithm_pos = string.find(args.hash, ":", 1, true)

            -- If ":" found then strip "[hash]" part.
            if algorithm_pos then
                hash_algorithm = string.sub(args.hash, 1, algorithm_pos - 1)

                args.hash = string.sub(args.hash, algorithm_pos + 1)
            end

            hash_future = hash.digitize_file(hash_algorithm, args.path)
        end

        return false, nil
    end)
end
