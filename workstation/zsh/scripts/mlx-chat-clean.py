#!/usr/bin/env python3
"""Interactive MLX chat REPL that hides <think>...</think> reasoning traces.

mlx_lm.chat streams raw model output with no handling of reasoning tags, so a
thinking model (e.g. Qwen3) dumps its entire chain-of-thought inline with the
final answer, unbroken, un-truncated-safely, at the default 256-token cap —
which is what produces the unreadable wall of text. This wraps the same
stream_generate loop, buffers just enough to detect <think>/</think> tag
boundaries split across streamed chunks, and only prints the final answer
(with a "(thinking...)" placeholder while reasoning runs) unless --show-thinking
is passed.
"""

import argparse

import mlx.core as mx
from mlx_lm.generate import stream_generate
from mlx_lm.models.cache import make_prompt_cache
from mlx_lm.sample_utils import make_sampler
from mlx_lm.utils import load

DEFAULT_MODEL = "mlx-community/Qwen3.6-35B-A3B-4bit"
DEFAULT_MAX_TOKENS = 4096
THINK_OPEN = "<think>"
THINK_CLOSE = "</think>"
MAX_TAG_LEN = max(len(THINK_OPEN), len(THINK_CLOSE))


def build_arg_parser():
    parser = argparse.ArgumentParser(description="Chat with an MLX model, reasoning trace hidden by default.")
    parser.add_argument("--model", type=str, default=DEFAULT_MODEL)
    parser.add_argument("--temp", type=float, default=0.0)
    parser.add_argument("--top-p", type=float, default=1.0)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--max-kv-size", type=int, default=None)
    parser.add_argument("--max-tokens", "-m", type=int, default=DEFAULT_MAX_TOKENS)
    parser.add_argument("--system-prompt", default=None)
    parser.add_argument(
        "--show-thinking",
        action="store_true",
        help="Print the reasoning trace (dimmed) instead of hiding it.",
    )
    return parser


class ThinkFilter:
    """Streams text through, stripping <think>...</think> spans.

    Feed streamed chunks in with .push(); it prints as it goes, holding back
    only the trailing MAX_TAG_LEN-1 chars needed to detect a tag split across
    chunk boundaries. Call .close() once the stream ends to flush the rest.
    """

    def __init__(self, show_thinking):
        self.buf = ""
        self.thinking = False
        self.announced = False
        self.show_thinking = show_thinking

    def push(self, text):
        self.buf += text
        self._drain(final=False)

    def close(self):
        self._drain(final=True)
        if self.thinking and self.show_thinking:
            print()

    def _drain(self, final):
        while True:
            if not self.thinking:
                idx = self.buf.find(THINK_OPEN)
                if idx != -1:
                    self._emit(self.buf[:idx])
                    self.buf = self.buf[idx + len(THINK_OPEN):]
                    self.thinking = True
                    self.announced = False
                    continue
                safe_len = len(self.buf) if final else max(0, len(self.buf) - (MAX_TAG_LEN - 1))
                if safe_len:
                    self._emit(self.buf[:safe_len])
                    self.buf = self.buf[safe_len:]
                break
            else:
                idx = self.buf.find(THINK_CLOSE)
                if idx != -1:
                    if self.show_thinking:
                        self._emit_thinking(self.buf[:idx])
                    self.buf = self.buf[idx + len(THINK_CLOSE):]
                    self.thinking = False
                    continue
                safe_len = len(self.buf) if final else max(0, len(self.buf) - (MAX_TAG_LEN - 1))
                if safe_len:
                    if self.show_thinking:
                        self._emit_thinking(self.buf[:safe_len])
                    elif not self.announced:
                        print("\033[2m(thinking...)\033[0m", end="", flush=True)
                        self.announced = True
                    self.buf = self.buf[safe_len:]
                break

    def _emit(self, text):
        if text:
            print(text, end="", flush=True)

    def _emit_thinking(self, text):
        if text:
            print(f"\033[2m{text}\033[0m", end="", flush=True)


def print_help():
    print("The command list:")
    print("- 'q' to exit")
    print("- 'r' to reset the chat")
    print("- 't' to toggle showing the reasoning trace")
    print("- 'h' to display these commands")


def main():
    args = build_arg_parser().parse_args()
    mx.random.seed(args.seed)

    print(f"[INFO] Loading {args.model}...")
    model, tokenizer = load(args.model)[:2]
    print_help()

    show_thinking = args.show_thinking
    prompt_cache = make_prompt_cache(model, args.max_kv_size)
    while True:
        query = input(">> ")
        if query == "q":
            break
        if query == "r":
            prompt_cache = make_prompt_cache(model, args.max_kv_size)
            print("[reset]")
            continue
        if query == "t":
            show_thinking = not show_thinking
            print(f"[showing thinking: {show_thinking}]")
            continue
        if query == "h":
            print_help()
            continue

        messages = []
        if args.system_prompt is not None:
            messages.append({"role": "system", "content": args.system_prompt})
        messages.append({"role": "user", "content": query})
        prompt = tokenizer.apply_chat_template(messages, add_generation_prompt=True)

        filt = ThinkFilter(show_thinking)
        for response in stream_generate(
            model,
            tokenizer,
            prompt,
            max_tokens=args.max_tokens,
            sampler=make_sampler(args.temp, args.top_p),
            prompt_cache=prompt_cache,
        ):
            filt.push(response.text)
        filt.close()
        print()


if __name__ == "__main__":
    main()
