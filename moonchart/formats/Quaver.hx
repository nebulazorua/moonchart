package moonchart.formats;

import backend.Timing;
import formats.BasicFormat.BasicBPMChange;
import formats.BasicFormat.BasicChart;
import formats.BasicFormat.BasicMetaData;
import formats.BasicFormat.BasicMetaValues;
import formats.BasicFormat.BasicNote;
import openfl.Assets;
import parsers.QuaverParser;

class Quaver extends BasicFormat<QuaverFormat, {}>
{
	var parser:QuaverParser;

	public function new(?data:QuaverFormat)
	{
		super({timeFormat: MILLISECONDS, supportsEvents: true});
		this.data = data;
		parser = new QuaverParser();
	}

	override function fromBasicFormat(chart:BasicChart, ?diff:String):Quaver
	{
		diff ??= this.diff;
		var basicNotes = Timing.resolveDiffNotes(chart, diff);

		var hitObjects:Array<QuaverHitObject> = [];
		for (note in basicNotes)
		{
			hitObjects.push({
				StartTime: Std.int(note.time),
				EndTime: note.length > 0 ? Std.int(note.length) : null,
				Lane: note.lane,
				KeySounds: [] // Too lazy to add support for these rn
			});
		}

		var timingPoints:Array<QuaverTimingPoint> = [];
		for (change in chart.meta.bpmChanges)
		{
			timingPoints.push({
				StartTime: Std.int(change.time),
				Bpm: change.bpm
			});
		}

		this.data = {
			AudioFile: "audio.mp3", // TODO: could maybe add some metadata for this?
			BackgroundFile: "''",
			MapId: 0,
			MapSetId: 0,
			Mode: "Keys4",
			Artist: "a",
			Source: "a",
			Tags: "a",
			Creator: "a",
			Description: "a",
			BPMDoesNotAffectScrollVelocity: true,
			InitialScrollVelocity: chart.meta.extraData.get(SCROLL_SPEED) ?? 1.0,
			EditorLayers: [],
			CustomAudioSamples: [],
			SoundEffects: [],
			SliderVelocities: [],

			Title: chart.meta.title,
			TimingPoints: timingPoints,
			HitObjects: hitObjects,
			DifficultyName: diff
		}

		return this;
	}

	override function getNotes():Array<BasicNote>
	{
		var notes:Array<BasicNote> = [];

		for (hitObject in data.HitObjects)
		{
			var time:Int = hitObject.StartTime;
			var length:Int = (hitObject.EndTime != null) ? hitObject.EndTime - time : 0;

			notes.push({
				time: time,
				length: length,
				lane: hitObject.Lane,
				type: ""
			});
		}

		return notes;
	}

	override function getChartMeta():BasicMetaData
	{
		var bpmChanges:Array<BasicBPMChange> = [];

		for (timingPoint in data.TimingPoints)
		{
			bpmChanges.push({
				time: timingPoint.StartTime,
				bpm: timingPoint.Bpm,
				beatsPerMeasure: 4,
				stepsPerBeat: 4
			});
		}

		return {
			title: data.Title,
			bpmChanges: bpmChanges,
			extraData: [SCROLL_SPEED => data.InitialScrollVelocity]
		}
	}

	override function stringify()
	{
		return {
			data: parser.stringify(data),
			meta: null
		}
	}

	override public function fromFile(path:String, ?meta:String, ?diff:String):Quaver
	{
		return fromQuaver(Assets.getText(path));
	}

	public function fromQuaver(data:String /*, ?diff:String*/):Quaver
	{
		this.data = parser.parse(data);
		// this.diff = diff ?? this.data.Metadata.Version;
		return this;
	}
}
