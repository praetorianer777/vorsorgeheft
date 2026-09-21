import 'occurrence.dart';

/// The examinations of the first days of life, which in practice happen in the
/// maternity clinic and are rarely recorded one by one afterwards.
const newbornExaminationIds = {
  'u1',
  'newborn-screening',
  'cf-screening',
  'hearing-screening',
  'pulse-oximetry',
};

/// The newborn examinations whose window has closed with nothing recorded.
///
/// A child added three weeks after birth otherwise opens on five red entries
/// for things that almost certainly happened before discharge. Offering to
/// record them in one go is the app's way of saying so without assuming it.
List<Occurrence> unrecordedNewbornExaminations(List<Occurrence> timeline) => [
  for (final occurrence in timeline)
    if (newbornExaminationIds.contains(occurrence.rule.id) &&
        (occurrence.status == OccurrenceStatus.overdue ||
            occurrence.status == OccurrenceStatus.expired))
      occurrence,
];
