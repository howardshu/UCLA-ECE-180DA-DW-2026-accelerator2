#!/usr/bin/env python3
"""Bit-exact reference model of the MNIST CNN accelerator.

Semantics were inferred from the instructor golden vectors and match all six
(a1, p1, a2, p2, logits, argmax) exactly:

  * activations are stored HWC:          act[(h*W + w)*C + c]
  * conv weights are [oc][kh][kw][ic]:   wgt[base + ((o*K + r)*K + s)*C + c]
  * fc weights are [o][i]:               wgt[0x180 + o*48 + i]
  * conv requant: acc = bias + sum(x*w); out = clamp(acc >>> shift, 0, 255)
  * fc:           logit = bias + sum(p2*w), int32, no shift, no ReLU
  * argmax:       first (lowest-index) maximum   -- tie rule NOT confirmed

Usage:
  cnn_ref.py check <vector_dir>...          compare against golden_*.hex
  cnn_ref.py gen <out_dir> --seed N [...]   make a new vector + golden files
  cnn_ref.py trace <vector_dir> --layer conv1 --h 0 --w 0
                                            print every MAC for one output
"""
import argparse
import os
import random
import sys

IMG_H = IMG_W = 28
K = 5
OC = 3
FLAT = 48
FC_O = 10
WGT_CONV1_BASE, WGT_CONV2_BASE, WGT_FC_BASE = 0x000, 0x080, 0x180
PAR_MAGIC, PAR_VERSION, PAR_SHIFT1, PAR_SHIFT2 = 0, 1, 2, 3
PAR_CONV1_B, PAR_CONV2_B, PAR_FC_B = 4, 7, 10
MAGIC, VERSION = 0x434E4E01, 1
IMG_SLOT_BYTES = 1024


# ----- hex I/O (one value per line, same format as the course vectors) -----
def read_hex(path, bits=None):
    vals = [int(l.split('//')[0].strip(), 16) for l in open(path)
            if l.split('//')[0].strip()]
    if bits:
        m = 1 << bits
        vals = [v - m if v >= m // 2 else v for v in vals]
    return vals


def write_hex(path, vals, bits):
    digits = bits // 4
    mask = (1 << bits) - 1
    with open(path, 'w') as f:
        for v in vals:
            f.write(f'{v & mask:0{digits}x}\n')


# ----- layers -----
def requant(acc, shift):
    return max(0, min(255, acc >> shift))   # Python >> is arithmetic


def conv(x, H, W, C, wgt, base, bias, shift, trace=None):
    OH, OW = H - K + 1, W - K + 1
    out = [0] * (OH * OW * OC)
    for h in range(OH):
        for w in range(OW):
            for o in range(OC):
                acc = bias[o]
                for r in range(K):
                    for s in range(K):
                        for c in range(C):
                            xi = ((h + r) * W + (w + s)) * C + c
                            wi = base + ((o * K + r) * K + s) * C + c
                            acc += x[xi] * wgt[wi]
                            if trace and trace(h, w, o):
                                print(f'  o={o} r={r} s={s} c={c} x[{xi}]={x[xi]:3d} '
                                      f'w[0x{wi:03x}]={wgt[wi]:4d} acc={acc}')
                out[(h * OW + w) * OC + o] = requant(acc, shift)
    return out, OH, OW


def pool(x, H, W, C):
    OH, OW = H // 2, W // 2
    out = [0] * (OH * OW * C)
    for h in range(OH):
        for w in range(OW):
            for c in range(C):
                out[(h * OW + w) * C + c] = max(
                    x[((2 * h + a) * W + (2 * w + b)) * C + c]
                    for a in (0, 1) for b in (0, 1))
    return out


def fc(x, wgt, bias):
    return [bias[o] + sum(x[i] * wgt[WGT_FC_BASE + o * FLAT + i] for i in range(FLAT))
            for o in range(FC_O)]


def argmax(logits):
    best = 0
    for i in range(1, len(logits)):
        if logits[i] > logits[best]:
            best = i
    return best


def run(img_mem, wgt, par, offset, trace=None):
    x = img_mem[offset:offset + IMG_H * IMG_W]
    a1, h, w = conv(x, IMG_H, IMG_W, 1, wgt, WGT_CONV1_BASE,
                    par[PAR_CONV1_B:PAR_CONV1_B + 3], par[PAR_SHIFT1],
                    trace.get('conv1') if trace else None)
    p1 = pool(a1, h, w, OC)
    a2, h, w = conv(p1, h // 2, w // 2, OC, wgt, WGT_CONV2_BASE,
                    par[PAR_CONV2_B:PAR_CONV2_B + 3], par[PAR_SHIFT2],
                    trace.get('conv2') if trace else None)
    p2 = pool(a2, h, w, OC)
    logits = fc(p2, wgt, par[PAR_FC_B:PAR_FC_B + FC_O])
    return dict(a1=a1, p1=p1, a2=a2, p2=p2, logits=logits, argmax=argmax(logits))


def expected_res(r):
    # RES memory: words 0..9 logits, 10 argmax, 11 MAGIC, 12..15 zero
    return r['logits'] + [r['argmax'], MAGIC, 0, 0, 0, 0]


def load_vector(d):
    img = read_hex(f'{d}/img_mem.hex')
    wgt = read_hex(f'{d}/wgt_mem.hex', 8)
    par = read_hex(f'{d}/param_mem.hex', 32)
    return img, wgt, par


def vector_offset(d):
    summ = os.path.join(d, 'summary.txt')
    if os.path.exists(summ):
        for line in open(summ):
            if line.startswith('image offset'):
                return int(line.split(':')[1].strip(), 16)
    return 0


# ----- commands -----
def cmd_check(args):
    fails = 0
    for d in args.dirs:
        img, wgt, par = load_vector(d)
        r = run(img, wgt, par, vector_offset(d))
        res = []
        for name in ('a1', 'p1', 'a2', 'p2'):
            gold = read_hex(f'{d}/golden_{name}.hex')
            res.append((name, r[name] == gold))
        exp = read_hex(f'{d}/expected.hex')
        res.append(('res', [v & 0xffffffff for v in expected_res(r)] == exp))
        ok = all(v for _, v in res)
        fails += not ok
        print(f'{"ok  " if ok else "FAIL"} {os.path.basename(os.path.normpath(d)):12s} '
              + ' '.join(f'{n}={"ok" if v else "X"}' for n, v in res)
              + f'  digit={r["argmax"]}')
    return 1 if fails else 0


def cmd_gen(args):
    rng = random.Random(args.seed)
    os.makedirs(args.out, exist_ok=True)
    img = [0] * 2048
    off = args.offset
    for i in range(784):
        img[off + i] = rng.randrange(256) if args.image == 'random' else args.image_value
    wgt = [0] * 1024
    for base, n in ((WGT_CONV1_BASE, 75), (WGT_CONV2_BASE, 225), (WGT_FC_BASE, 480)):
        for i in range(n):
            wgt[base + i] = rng.randrange(-128, 128)
    par = [0] * 32
    par[PAR_MAGIC], par[PAR_VERSION] = MAGIC, VERSION
    par[PAR_SHIFT1], par[PAR_SHIFT2] = args.shift1, args.shift2
    for i in range(16):
        par[PAR_CONV1_B + i] = rng.randrange(-args.bias_range, args.bias_range)
    r = run(img, wgt, par, off)
    write_hex(f'{args.out}/img_mem.hex', img, 8)
    write_hex(f'{args.out}/wgt_mem.hex', wgt, 8)
    write_hex(f'{args.out}/param_mem.hex', par, 32)
    for name in ('a1', 'p1', 'a2', 'p2'):
        write_hex(f'{args.out}/golden_{name}.hex', r[name], 8)
    write_hex(f'{args.out}/expected.hex', expected_res(r), 32)
    with open(f'{args.out}/summary.txt', 'w') as f:
        f.write(f'vector        : {os.path.basename(os.path.normpath(args.out))}\n')
        f.write(f'seed          : {args.seed}\n')
        f.write(f'image offset  : 0x{off:03x}\n')
        f.write(f'shift1,shift2 : {args.shift1}, {args.shift2}\n')
        f.write(f'conv1 out     : {sum(v > 0 for v in r["a1"])}/1728 nonzero, '
                f'{sum(v == 255 for v in r["a1"])} saturated\n')
        f.write(f'conv2 out     : {sum(v > 0 for v in r["a2"])}/192 nonzero, '
                f'{sum(v == 255 for v in r["a2"])} saturated\n')
        f.write(f'logits        : {r["logits"]}\n')
        f.write(f'predicted     : {r["argmax"]}\n')
    print(f'wrote {args.out}: digit={r["argmax"]}')
    return 0


def cmd_trace(args):
    img, wgt, par = load_vector(args.dir)
    want = (args.h, args.w, args.o)
    sel = {args.layer: lambda h, w, o: (h, w, o) == want}
    r = run(img, wgt, par, vector_offset(args.dir), trace=sel)
    name = 'a1' if args.layer == 'conv1' else 'a2'
    OW = 24 if args.layer == 'conv1' else 8
    print(f'{name}[{(args.h * OW + args.w) * OC + args.o}] = '
          f'{r[name][(args.h * OW + args.w) * OC + args.o]}')
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)
    c = sub.add_parser('check')
    c.add_argument('dirs', nargs='+')
    g = sub.add_parser('gen')
    g.add_argument('out')
    g.add_argument('--seed', type=int, default=0)
    g.add_argument('--offset', type=lambda s: int(s, 0), default=0)
    g.add_argument('--shift1', type=int, default=8)
    g.add_argument('--shift2', type=int, default=8)
    g.add_argument('--bias-range', type=int, default=4096)
    g.add_argument('--image', choices=['random', 'const'], default='random')
    g.add_argument('--image-value', type=int, default=0)
    t = sub.add_parser('trace')
    t.add_argument('dir')
    t.add_argument('--layer', choices=['conv1', 'conv2'], default='conv1')
    t.add_argument('--h', type=int, default=0)
    t.add_argument('--w', type=int, default=0)
    t.add_argument('--o', type=int, default=0)
    args = ap.parse_args()
    return {'check': cmd_check, 'gen': cmd_gen, 'trace': cmd_trace}[args.cmd](args)


if __name__ == '__main__':
    sys.exit(main())
