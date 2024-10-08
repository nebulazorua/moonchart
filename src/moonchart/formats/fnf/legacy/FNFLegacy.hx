package moonchart.formats.fnf.legacy;

import moonchart.backend.FormatData;
import moonchart.backend.Util;
import moonchart.backend.Timing;
import moonchart.formats.BasicFormat;
import moonchart.formats.fnf.FNFVSlice;
import haxe.Json;

using StringTools;

typedef FNFLegacyFormat =
{
	song:String,
	bpm:Float,
	speed:Float,
	needsVoices:Bool,
	validScore:Bool,
	player1:String,
	player2:String,
	notes:Array<FNFLegacySection>
}

typedef FNFLegacySection =
{
	mustHitSection:Bool,
	lengthInSteps:Int,
	sectionNotes:Array<FNFLegacyNote>,
	altAnim:Bool,
	changeBPM:Bool,
	bpm:Float
}

// TODO: FNF legacy and vslice (?) have the quirk of having lengths be 1 step crochet behind their actual length
// Should prob account for those, specially since formats like stepmania exist that require very specific hold lengths

abstract FNFLegacyNote(Array<Dynamic>) from Array<Dynamic> to Array<Dynamic>
{
	public var time(get, never):Float;
	public var lane(get, never):Int;
	public var length(get, never):Float;
	public var type(get, never):Dynamic;

	inline function get_time():Float
	{
		return this[0];
	}

	inline function get_lane():Int
	{
		return this[1];
	}

	inline function get_length():Float
	{
		return this[2];
	}

	inline function get_type():Dynamic
	{
		return this[3];
	}
}

enum abstract FNFLegacyNoteType(String) from String to String
{
	var DEFAULT = "";
	var ALT_ANIM = "ALT_ANIM";
	var HURT = "HURT";
}

enum abstract FNFLegacyEvent(String) from String to String
{
	var MUST_HIT_SECTION = "FNF_MUST_HIT_SECTION";
}

enum abstract FNFLegacyMetaValues(String) from String to String
{
	var PLAYER_1 = "FNF_P1";
	var PLAYER_2 = "FNF_P2";
	var PLAYER_3 = "FNF_P3";
	var STAGE = "FNF_STAGE";
	var NEEDS_VOICES = "FNF_NEEDS_VOICES";
	var VOCALS_OFFSET = "FNF_VOCALS_OFFSET";
	var MAIN_MUSTHIT = "FNF_MAIN_MUSTHIT";
	var SWITCH_LANES = "FNF_SWITCH_LANES";
}

typedef FNFLegacy = FNFLegacyBasic<FNFLegacyFormat>;

@:private
class FNFLegacyBasic<T:FNFLegacyFormat> extends BasicFormat<{song:T}, {}>
{
	public static function __getFormat():FormatData
	{
		return {
			ID: FNF_LEGACY,
			name: "FNF (Legacy)",
			description: "The original section-based FNF format.",
			extension: "json",
			hasMetaFile: FALSE,
			handler: FNFLegacy
		};
	}

	/**
	 * The default must hit section value.
	 *
	 * It is recommended to set this to `true` when converting single-dance charts,
	 * and to `false` for double-dance charts.
	 */
	public static var FNF_LEGACY_DEFAULT_MUSTHIT:Bool = true;

	public function new(?data:{song:T})
	{
		super({timeFormat: MILLISECONDS, supportsDiffs: false, supportsEvents: false});
		this.data = data;
	}

	override function fromBasicFormat(chart:BasicChart, ?diff:FormatDifficulty):FNFLegacyBasic<T>
	{
		var chartResolve = resolveDiffsNotes(chart, diff);
		var diff:String = chartResolve.diffs[0];
		var basicNotes:Array<BasicNote> = chartResolve.notes.get(diff);

		var meta = chart.meta;
		var initBpm = meta.bpmChanges[0].bpm;

		var notes:Array<FNFLegacySection> = [];
		var measures = Timing.divideNotesToMeasures(basicNotes, chart.data.events, meta.bpmChanges);
		var switchLanes:Bool = chart.meta.extraData.get(SWITCH_LANES) ?? true;

		// Take out must hit events
		chart.data.events = FNFVSlice.filterEvents(chart.data.events);

		var lastBpm = initBpm;
		var lastMustHit:Bool = FNFLegacy.FNF_LEGACY_DEFAULT_MUSTHIT;
		var nextMustHit:Null<Bool> = null;

		for (measure in measures)
		{
			var mustHit:Bool = lastMustHit;

			if (nextMustHit != null)
			{
				mustHit = nextMustHit;
				nextMustHit = null;
			}

			// Push must hit events
			for (event in measure.events)
			{
				// Check if measure has a must hit event
				if (FNFVSlice.isCamFocusEvent(event))
				{
					var eventMustHit = FNFVSlice.resolveCamFocus(event) == 0;
					var eventTime = (event.time - measure.startTime);
					if (eventTime < measure.length / 2)
					{
						mustHit = eventMustHit;
						nextMustHit = null;
					}
					else
					{
						// Event happens too late, save it for the next measure (aprox)
						nextMustHit = eventMustHit;
					}
				}
			}

			// Create legacy section
			var section:FNFLegacySection = {
				sectionNotes: [],
				mustHitSection: mustHit,
				lengthInSteps: Std.int(measure.stepsPerBeat * measure.beatsPerMeasure),
				altAnim: false,
				changeBPM: false,
				bpm: 0.0
			}

			lastMustHit = mustHit;

			// Section has a bpm change event (aprox)
			if (measure.bpm != lastBpm)
			{
				section.changeBPM = true;
				section.bpm = measure.bpm;
				lastBpm = measure.bpm;
			}

			final stepCrochet:Float = Timing.stepCrochet(measure.bpm, measure.stepsPerBeat);

			// Push notes to section
			for (note in measure.notes)
			{
				final lane:Int = switchLanes ? mustHitLane(mustHit, note.lane) : mustHitLane(mustHit, (note.lane + 4) % 8);
				final length:Float = note.length > 0 ? Math.max(note.length - stepCrochet, 0) : 0;

				final fnfNote:FNFLegacyNote = [note.time, lane, length, note.type];
				section.sectionNotes.push(fnfNote);
			}

			notes.push(section);
		}

		this.data = cast {
			song: {
				song: meta.title,
				bpm: initBpm,
				speed: meta.scrollSpeeds.get(diff) ?? 1.0,
				needsVoices: meta.extraData.get(NEEDS_VOICES) ?? false,
				validScore: true,
				player1: meta.extraData.get(PLAYER_1) ?? "bf",
				player2: meta.extraData.get(PLAYER_2) ?? "dad",
				notes: notes
			}
		};

		return this;
	}

	public function filterEvents(events:Array<BasicEvent>):Array<BasicEvent>
	{
		return FNFVSlice.filterEvents(events);
	}

	public static function resolveNoteType(note:FNFLegacyNote):String
	{
		if (note.type is String)
		{
			return note.type;
		}

		return switch (cast(note.type, Int))
		{
			case 0: DEFAULT;
			case 1: ALT_ANIM;
			case _: DEFAULT;
		}
	}

	override function getNotes(?diff:String):Array<BasicNote>
	{
		var notes:Array<BasicNote> = [];

		var stepCrochet = Timing.stepCrochet(data.song.bpm, 4);

		for (section in data.song.notes)
		{
			if (section.changeBPM)
			{
				stepCrochet = Timing.stepCrochet(section.bpm, 4);
			}

			for (note in section.sectionNotes)
			{
				var lane:Int = mustHitLane(section.mustHitSection, note.lane);
				var length:Float = note.length > 0 ? note.length + stepCrochet : 0;
				var type:String = section.altAnim ? ALT_ANIM : resolveNoteType(note);

				notes.push({
					time: note.time,
					lane: lane,
					length: length,
					type: type
				});
			}
		}

		Timing.sortNotes(notes);

		return notes;
	}

	public static inline function mustHitLane(mustHit:Bool, lane:Int):Int
	{
		// TODO: Maybe some add some metadata for extrakey formats?
		return (mustHit ? lane : (lane + 4) % 8);
	}

	public static inline function makeMustHitSectionEvent(time:Float, mustHit:Bool):BasicEvent
	{
		return {
			time: time,
			name: MUST_HIT_SECTION,
			data: {
				mustHitSection: mustHit
			}
		}
	}

	override function getEvents():Array<BasicEvent>
	{
		var events:Array<BasicEvent> = [];
		var lastMustHit:Bool = FNF_LEGACY_DEFAULT_MUSTHIT;

		// Push musthit events
		forEachSection(data.song.notes, (section, startTime, endTime) ->
		{
			if (section.mustHitSection != lastMustHit)
			{
				events.push(makeMustHitSectionEvent(startTime, section.mustHitSection));
				lastMustHit = section.mustHitSection;
			}
		});

		return events;
	}

	function forEachSection(sections:Array<FNFLegacySection>, call:(FNFLegacySection, Float, Float) -> Void)
	{
		var time:Float = 0;
		var crochet = Timing.measureCrochet(data.song.bpm, 4);

		for (section in sections)
		{
			if (section.changeBPM)
			{
				var beats:Float = sectionBeats(section);
				crochet = Timing.measureCrochet(section.bpm, beats);
			}

			call(section, time, time + crochet);
			time += crochet;
		}
	}

	function sectionBeats(?section:FNFLegacySection):Float
	{
		return Std.int((section?.lengthInSteps ?? 16) / 4);
	}

	override function getChartMeta():BasicMetaData
	{
		var bpmChanges:Array<BasicBPMChange> = [];

		var time:Float = 0.0;
		var bpm:Float = data.song.bpm;
		var beats:Float = sectionBeats(data.song.notes[0]);
		var crochet:Float = Timing.measureCrochet(bpm, beats);

		bpmChanges.push({
			time: time,
			bpm: bpm,
			beatsPerMeasure: beats,
			stepsPerBeat: 4
		});

		for (section in data.song.notes)
		{
			beats = sectionBeats(data.song.notes[0]);

			if (section.changeBPM)
			{
				bpm = section.bpm;
				crochet = Timing.measureCrochet(bpm, beats);
				bpmChanges.push({
					time: time,
					bpm: bpm,
					beatsPerMeasure: beats,
					stepsPerBeat: 4
				});
			}

			time += crochet;
		}

		Timing.sortBPMChanges(bpmChanges);

		return {
			title: data.song.song,
			bpmChanges: bpmChanges,
			offset: 0.0,
			scrollSpeeds: [diffs[0] => data.song.speed],
			extraData: [
				PLAYER_1 => data.song.player1,
				PLAYER_2 => data.song.player2,
				NEEDS_VOICES => data.song.needsVoices,
				MAIN_MUSTHIT => FNF_LEGACY_DEFAULT_MUSTHIT
			]
		}
	}

	override function stringify()
	{
		return {
			data: Json.stringify(data),
			meta: Json.stringify(meta)
		}
	}

	public override function fromFile(path:String, ?meta:String, ?diff:FormatDifficulty):FNFLegacyBasic<T>
	{
		return fromJson(Util.getText(path), meta != null ? Util.getText(meta) : meta, diff);
	}

	public function fromJson(data:String, ?meta:String, ?diff:FormatDifficulty):FNFLegacyBasic<T>
	{
		this.diffs = diff;
		this.data = Json.parse(fixLegacyJson(data));
		return this;
	}

	// Old json charts were hyper fucked with corrupted data
	function fixLegacyJson(rawJson:String):String
	{
		var split = rawJson.split("}");
		var pop = split.length - 1;

		if (split[pop].length > 0)
			split[pop] = "";

		rawJson = split.join("}");

		return rawJson;
	}
}
