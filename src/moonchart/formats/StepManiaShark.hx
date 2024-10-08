package moonchart.formats;

import moonchart.backend.FormatData;
import moonchart.backend.Util;
import moonchart.backend.Timing;
import moonchart.formats.BasicFormat;
import moonchart.parsers.StepManiaSharkParser;
import moonchart.formats.StepMania.BasicStepMania;

// Extension of StepMania
class StepManiaShark extends BasicStepMania<SSCFormat>
{
	public static function __getFormat():FormatData
	{
		return {
			ID: STEPMANIA_SHARK,
			name: "StepManiaShark",
			description: "",
			extension: "ssc",
			hasMetaFile: FALSE,
			handler: StepManiaShark
		}
	}

	public function new(?data:SSCFormat)
	{
		super(data);
		this.data = data;
		parser = new StepManiaSharkParser();
	}

	// Mark labels as events cus that makes it usable for shit like FNF
	override function getEvents():Array<BasicEvent>
	{
		var events = super.getEvents();
		var bpmChanges = getChartMeta().bpmChanges;

		var labels = data.LABELS.copy();

		var lastTime:Float = 0;
		var lastBeat:Float = 0;
		var crochet:Float = Timing.crochet(bpmChanges.shift().bpm);

		// Add labels between bpm changes
		for (change in bpmChanges)
		{
			var elapsedTime:Float = change.time - lastTime;
			var curBeat = lastBeat + (elapsedTime * crochet);

			while (labels.length > 0 && labels[0].beat <= curBeat)
			{
				var label = labels.shift();
				events.push({
					time: change.time + ((label.beat - curBeat) * crochet),
					name: label.label,
					data: {}
				});
			}

			crochet = Timing.crochet(change.bpm);
			lastTime = change.time;
			lastBeat = curBeat;
		}

		// Add any left over labels
		while (labels.length > 0)
		{
			var label = labels.shift();
			events.push({
				time: lastTime + ((label.beat - lastBeat) * crochet),
				name: label.label,
				data: {}
			});
		}

		return events;
	}

	override public function fromFile(path:String, ?meta:String, ?diff:FormatDifficulty):StepManiaShark
	{
		return fromStepManiaShark(Util.getText(path), diff);
	}

	public function fromStepManiaShark(data:String, ?diff:FormatDifficulty):StepManiaShark
	{
		this.data = parser.parse(data);
		this.diffs = diff ?? Util.mapKeyArray(this.data.NOTES);
		return this;
	}
}
