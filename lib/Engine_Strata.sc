// Engine_Strata.sc
// digital geology instrument
// decay chain + quake + crystal + ghost FX
// vanilla UGens only

Engine_Strata : CroneEngine {
  var processSynth;
  var quakeSynth;
  var crystalSynth;
  var ghostSynth;
  var mixSynth;
  var ampBus;

  *new { |context, doneCallback| ^super.new(context, doneCallback) }

  alloc {
    var s, out_bus, in_bus;
    s = context.server;

    out_bus = if(context.out_b.isKindOf(Array),
      { context.out_b[0].index }, { context.out_b.index });
    in_bus = if(context.in_b.isKindOf(Array),
      { context.in_b[0].index }, { context.in_b.index });

    ampBus = Bus.control(s, 2);

    // -- decay processing chain --
    SynthDef(\strata_process, {
      arg in_bus, out_bus,
          bit_depth=16, srate=48000,
          cutoff=20000, width=1.0,
          noise=0.0, drift=0.0,
          decay_mix=0.0, amp=0.5;
      var sig, dry, steps, crushed;
      var sig_l, sig_r, mid, side;

      sig = In.ar(in_bus, 2);
      dry = sig;

      // bit crush (vanilla: quantize amplitude)
      steps = (2.pow(bit_depth.clip(1, 16) - 1)).max(1);
      crushed = (sig * steps).round / steps;

      // sample rate reduce (vanilla: Latch + Impulse)
      crushed = Latch.ar(crushed, Impulse.ar(srate.clip(500, 48000)));

      // lowpass
      crushed = LPF.ar(crushed, cutoff.clip(100, 20000));

      // stereo width (mid/side)
      sig_l = crushed[0]; sig_r = crushed[1];
      mid = (sig_l + sig_r) * 0.5;
      side = (sig_l - sig_r) * 0.5 * width.clip(0, 1);
      crushed = [mid + side, mid - side];

      // noise floor
      crushed = crushed + (WhiteNoise.ar(noise.clip(0, 0.5)) ! 2);

      // pitch drift
      crushed = PitchShift.ar(crushed, 0.2,
        drift.clip(-2, 2).midiratio, 0.01, 0.04);

      // mix dry/processed
      sig = (dry * (1 - decay_mix)) + (crushed * decay_mix);
      sig = Limiter.ar(sig * amp, 0.95);
      Out.ar(out_bus, sig);

      // amplitude poll
      Out.kr(ampBus.index, [
        Amplitude.kr(sig[0], 0.01, 0.1),
        Amplitude.kr(sig[1], 0.01, 0.1)
      ]);
    }).add;

    // -- earthquake burst --
    SynthDef(\strata_quake, {
      arg out_bus, intensity=0.5, dur=3;
      var sig, env, noise;
      env = EnvGen.ar(
        Env.perc(0.01, dur, 1, -6),
        doneAction: Done.freeSelf);
      noise = WhiteNoise.ar(0.3) + Dust.ar(200 * intensity);
      sig = noise;
      // allpass cascade for metallic ring
      4.do { sig = AllpassC.ar(sig, 0.1,
        LFNoise1.kr(0.5).range(0.01, 0.08), 2) };
      // pitch sweep
      sig = PitchShift.ar(sig, 0.1,
        LFNoise1.kr(3).range(0.5, 2.0), 0.02, 0.08);
      sig = LPF.ar(sig, 3000 * intensity + 500);
      sig = Pan2.ar(sig.sum, LFNoise1.kr(2));
      sig = sig * env * intensity * 0.4;
      Out.ar(out_bus, sig);
    }).add;

    // -- crystallization drone --
    SynthDef(\strata_crystal, {
      arg out_bus, freq=220, feedback=0.9,
          amp=0.3, gate=1;
      var sig, env, exc;
      env = EnvGen.ar(
        Env.asr(2, 1, 3, -4), gate,
        doneAction: Done.freeSelf);
      // gentle excitation
      exc = Dust.ar(5) * 0.1 + (PinkNoise.ar * 0.02);
      // comb bank at harmonic series
      sig = CombC.ar(exc, 0.5, freq.reciprocal, feedback * 8)
          + CombC.ar(exc, 0.5, (freq * 2).reciprocal, feedback * 6)
          + CombC.ar(exc, 0.5, (freq * 3).reciprocal, feedback * 4)
          + CombC.ar(exc, 0.5, (freq * 5).reciprocal, feedback * 3);
      sig = Resonz.ar(sig, freq, 0.01) * 20;
      sig = sig + Resonz.ar(sig, freq * 2, 0.02) * 10;
      sig = Limiter.ar(sig, 0.8);
      sig = Pan2.ar(sig, SinOsc.kr(0.05));
      sig = sig * env * amp;
      Out.ar(out_bus, sig);
    }).add;

    // -- ghost processing --
    SynthDef(\strata_ghost, {
      arg out_bus,
          shift=(-12), verb=0.8, hpf=800,
          amp=0.3, gate=1;
      var sig, env, in_sig;
      env = EnvGen.ar(
        Env.asr(3, 1, 5, -4), gate,
        doneAction: Done.freeSelf);
      in_sig = In.ar(out_bus, 2);
      // pitch shift (semitones)
      sig = PitchShift.ar(in_sig, 0.3,
        shift.midiratio, 0.02, 0.1);
      sig = HPF.ar(sig, hpf.clip(100, 5000));
      // long reverb
      sig = FreeVerb2.ar(sig[0], sig[1],
        verb.clip(0, 1), 0.9, 0.5);
      // breathing modulation
      sig = sig * SinOsc.kr(0.15, 0, 0.3, 0.7);
      sig = sig * env * amp;
      Out.ar(out_bus, sig);
    }).add;

    context.server.sync;

    // start process synth
    processSynth = Synth(\strata_process, [
      \in_bus, in_bus,
      \out_bus, out_bus,
      \decay_mix, 0.0,
      \amp, 0.5
    ], context.xg);

    // -- commands --

    // decay chain params
    this.addCommand("decay", "ffffff", { arg msg;
      processSynth.set(
        \bit_depth, msg[1].asFloat,
        \srate, msg[2].asFloat,
        \cutoff, msg[3].asFloat,
        \width, msg[4].asFloat,
        \noise, msg[5].asFloat,
        \drift, msg[6].asFloat
      );
    });

    this.addCommand("decay_mix", "f", { arg msg;
      processSynth.set(\decay_mix, msg[1].asFloat);
    });

    this.addCommand("amp", "f", { arg msg;
      processSynth.set(\amp, msg[1].asFloat);
    });

    // earthquake
    this.addCommand("quake", "ff", { arg msg;
      Synth(\strata_quake, [
        \out_bus, out_bus,
        \intensity, msg[1].asFloat,
        \dur, msg[2].asFloat
      ], context.xg);
    });

    // crystal start
    this.addCommand("crystal_start", "fff", { arg msg;
      if(crystalSynth.notNil, { crystalSynth.set(\gate, 0) });
      crystalSynth = Synth(\strata_crystal, [
        \out_bus, out_bus,
        \freq, msg[1].asFloat,
        \feedback, msg[2].asFloat,
        \amp, msg[3].asFloat
      ], context.xg);
    });

    this.addCommand("crystal_stop", "", { arg msg;
      if(crystalSynth.notNil, {
        crystalSynth.set(\gate, 0);
        crystalSynth = nil;
      });
    });

    // ghost
    this.addCommand("ghost_start", "ffff", { arg msg;
      if(ghostSynth.notNil, { ghostSynth.set(\gate, 0) });
      ghostSynth = Synth(\strata_ghost, [
        \out_bus, out_bus,
        \shift, msg[1].asFloat,
        \verb, msg[2].asFloat,
        \hpf, msg[3].asFloat,
        \amp, msg[4].asFloat
      ], context.xg);
    });

    this.addCommand("ghost_stop", "", { arg msg;
      if(ghostSynth.notNil, {
        ghostSynth.set(\gate, 0);
        ghostSynth = nil;
      });
    });

    // -- polls --
    this.addPoll("strata_amps", {
      var vals;
      vals = ampBus.getnSynchronous(2);
      vals[0].asString ++ "," ++ vals[1].asString;
    });
  }

  free {
    processSynth.free;
    if(crystalSynth.notNil, { crystalSynth.free });
    if(ghostSynth.notNil, { ghostSynth.free });
    ampBus.free;
  }
}
