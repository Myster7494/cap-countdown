import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:cap_countdown/main.dart';
import 'package:cap_countdown/src/exam/cap_subject.dart';
import 'package:cap_countdown/src/exam/exam_subject.dart';
import 'package:cap_countdown/src/exam/question_meta.dart';
import 'package:cap_countdown/src/exam/question_note.dart';
import 'package:cap_countdown/src/exam/subject_question.dart';
import 'package:cap_countdown/src/widgets/optional_question_view.dart';
import 'package:cap_countdown/src/widgets/subject_question_view.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class SimulationExamPage extends StatefulWidget {
  final int year;
  final String examName;
  final ExamSubject subject;

  const SimulationExamPage(
      {Key? key,
      required this.year,
      required this.examName,
      required this.subject})
      : super(key: key);

  @override
  State<SimulationExamPage> createState() => _SimulationExamPageState();
}

class _SimulationExamPageState extends State<SimulationExamPage> {
  final _pageController = PageController();

  int _currentPage = 0;
  bool _submitted = false;
  late bool _disablePageChange;

  @override
  void initState() {
    _disablePageChange =
        widget.subject.subjectId == CAPSubject.englishListening;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final questions = widget.subject.questions;
    final question = questions[_currentPage];
    final isFavorite = localStorage.favoriteQuestions.contains(question);
    final tookNote = localStorage.questionNotes.containsKey(question.hashCode);

    return WillPopScope(
      onWillPop: () async {
        // Prevent using system navigation to leave this page.
        _showBackDialog();

        return false;
      },
      child: Scaffold(
          appBar: AppBar(
            title: Text(widget.examName, style: const TextStyle(fontSize: 18)),
            actions: [
              IconButton(
                  onPressed: () {
                    _showNoteDialog(question);
                  },
                  icon: tookNote
                      ? Icon(Icons.draw_rounded,
                          color: Theme.of(context).colorScheme.primary)
                      : const Icon(Icons.draw_outlined),
                  tooltip: '做筆記'),
              IconButton(
                  onPressed: () {
                    if (isFavorite) {
                      question.removeFromFavorite();
                    } else {
                      question.addToFavorite();
                    }
                    setState(() {});
                  },
                  icon: isFavorite
                      ? const Icon(Icons.favorite, color: Colors.red)
                      : const Icon(Icons.favorite_border),
                  tooltip: isFavorite ? '取消收藏' : '加入收藏'),
            ],
            leading: BackButton(
              onPressed: () {
                _showBackDialog();
              },
            ),
          ),
          body: Column(
            children: [
              if (!_submitted)
                ExamTimer(
                  duration: widget.subject.duration,
                  onExamOver: () {
                    showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) {
                          return AlertDialog(
                            title: const Text('警告'),
                            content: const Text('考試時間已到，請勿繼續作答！'),
                            actions: [
                              TextButton(
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    _submit();
                                  },
                                  child: const Text('確定'))
                            ],
                          );
                        });
                  },
                ),
              if (_submitted) GradeMarkings(subject: widget.subject),
              const Divider(),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: questions.length,
                  physics: _disablePageChange
                      ? const NeverScrollableScrollPhysics()
                      : null,
                  itemBuilder: (context, index) {
                    final question = questions[index];

                    return _QuestionPage(
                      question: question,
                      meta: QuestionMeta(
                          year: widget.year,
                          subjectId: widget.subject.subjectId,
                          questionIndex: index),
                      option: QuestionViewOption(
                          showQuestionNumber: true,
                          submitted: _submitted,
                          onlyPlayAudioOnce: !_submitted,
                          onAudioPlayStateChanged: (state) {
                            setState(() {
                              _disablePageChange = state == PlayerState.playing;
                            });
                          }),
                    );
                  },
                  onPageChanged: (page) {
                    setState(() {
                      _currentPage = page;
                    });
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10.0),
                child: Column(
                  children: [
                    if (!_submitted && _currentPage == questions.length - 1)
                      _buildSubmitButton(),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              if (_disablePageChange) return;
                              _pageController.previousPage(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut);
                            },
                            style: ElevatedButton.styleFrom(
                                foregroundColor:
                                    _disablePageChange || _currentPage == 0
                                        ? Theme.of(context).disabledColor
                                        : null),
                            child: const Text('上一題'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        PageIndicator(
                          currentPage: _currentPage,
                          totalPages: questions.length,
                          enable: !_disablePageChange,
                          onPageChanged: (page) {
                            final isEnglishListening =
                                widget.subject.subjectId ==
                                    CAPSubject.englishListening;

                            // When the exam subject is English listening, disable the animation page change.
                            // Because if there is animation, the audio will be played when passing through each page.
                            if (isEnglishListening) {
                              _pageController.jumpToPage(page);
                              return;
                            }

                            _pageController.animateToPage(page,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut);
                          },
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              if (_disablePageChange) return;
                              if (_currentPage == questions.length - 1) return;

                              _pageController.nextPage(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut);
                            },
                            style: ElevatedButton.styleFrom(
                                foregroundColor: _disablePageChange
                                    ? Theme.of(context).disabledColor
                                    : null),
                            child: const Text('下一題'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          )),
    );
  }

  FloatingActionButton _buildSubmitButton() {
    return FloatingActionButton.extended(
        onPressed: () {
          final optionalQuestions = widget.subject.getOptionalQuestions();

          if (optionalQuestions.any((q) => q.selectedChoice == null)) {
            showDialog(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: const Text('確認交卷'),
                    content:
                        const Text('您尚有未作答的題目，您仍然要交卷嗎？\n還有一些時間，建議您可以繼續作答。'),
                    actions: [
                      TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          child: const Text('取消')),
                      TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            _submit();
                          },
                          child: const Text('確定'))
                    ],
                  );
                });

            return;
          }

          showDialog(
              context: context,
              builder: (context) {
                return AlertDialog(
                  title: const Text('確認交卷'),
                  content: const Text('您確定要交卷了嗎？\n還有一些時間，建議您可以先檢查看看再交卷。'),
                  actions: [
                    TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        child: const Text('取消')),
                    TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _submit();
                        },
                        child: const Text('確定'))
                  ],
                );
              });
        },
        icon: const Icon(Icons.done_rounded),
        label: const Text('交卷'));
  }

  void _showBackDialog() {
    if (_submitted) {
      widget.subject.clearRecords();
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }

    showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('確定要離開嗎？'),
            content: const Text('這將會清除本次的作答紀錄。'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  widget.subject.clearRecords();
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                child: const Text('確定'),
              ),
            ],
          );
        });
  }

  void _submit() {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('智慧老師正在為您批改考卷...'),
              content:
                  Lottie.asset('assets/animations/135507-exam-prep-topics.json',
                      onLoaded: (composition) async {
                await Future.delayed(const Duration(milliseconds: 2800));
                if (mounted) {
                  setState(() {
                    _submitted = true;
                    for (final question in widget.subject.questions) {
                      question.makeAsAnswered();
                    }
                  });
                  Navigator.of(context).pop();
                }
              }),
            ));
  }

  void _showNoteDialog(SubjectQuestion question) {
    final notes = localStorage.questionNotes;
    final note = notes[question.hashCode];
    final noteController = TextEditingController(text: note?.text ?? '');

    showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('筆記'),
            content: TextField(
              controller: noteController,
              maxLines: null,
              decoration: const InputDecoration(
                  border: OutlineInputBorder(), hintText: '請輸入筆記'),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  final text = noteController.text;
                  if (text.isNotEmpty) {
                    notes[question.hashCode] = QuestionNote(text: text);
                    localStorage.questionNotes = notes;
                  }

                  if (text.isEmpty && note != null && note.text.isNotEmpty) {
                    notes.remove(question.hashCode);
                    localStorage.questionNotes = notes;
                  }

                  Navigator.of(context).pop();
                  setState(() {});
                },
                child: const Text('確定'),
              ),
            ],
          );
        });
  }
}

class _QuestionPage extends StatefulWidget {
  const _QuestionPage({
    required this.question,
    required this.meta,
    required this.option,
  });

  final SubjectQuestion question;
  final QuestionMeta meta;
  final QuestionViewOption option;

  @override
  State<_QuestionPage> createState() => _QuestionPageState();
}

class _QuestionPageState extends State<_QuestionPage>
    with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SingleChildScrollView(
        child: Padding(
      padding: const EdgeInsets.all(16.0),
      child: SubjectQuestionView(
        question: widget.question,
        meta: widget.meta,
        option: widget.option,
      ),
    ));
  }

  @override
  bool get wantKeepAlive => true;
}

class PageIndicator extends StatefulWidget {
  final int currentPage;
  final int totalPages;
  final bool enable;
  final void Function(int page) onPageChanged;

  const PageIndicator(
      {super.key,
      required this.currentPage,
      required this.totalPages,
      required this.enable,
      required this.onPageChanged});

  @override
  State<PageIndicator> createState() => _PageIndicatorState();
}

class _PageIndicatorState extends State<PageIndicator> {
  late TextEditingController _textEditingController;
  int _inputPage = 1;

  @override
  void initState() {
    super.initState();
    _textEditingController =
        TextEditingController(text: '${widget.currentPage + 1}');
  }

  @override
  void dispose() {
    _textEditingController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PageIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentPage != oldWidget.currentPage) {
      _textEditingController.text = '${widget.currentPage + 1}';
      _inputPage = widget.currentPage + 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodyLarge;

    return Row(
      children: [
        SizedBox(
          height: 45,
          width: 40,
          child: TextField(
            controller: _textEditingController,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            onChanged: (text) {
              _inputPage = int.tryParse(text) ?? 1;
            },
            enabled: widget.enable,
            onSubmitted: (_) {
              _inputPage = _inputPage.clamp(1, widget.totalPages);
              _textEditingController.text = '$_inputPage';
              widget.onPageChanged(_inputPage - 1);
            },
          ),
        ),
        Text(' / ${widget.totalPages}', style: textStyle),
      ],
    );
  }
}

class ExamTimer extends StatefulWidget {
  final Duration duration;
  final void Function() onExamOver;

  const ExamTimer({
    super.key,
    required this.duration,
    required this.onExamOver,
  });

  @override
  State<ExamTimer> createState() => _ExamTimerState();
}

class _ExamTimerState extends State<ExamTimer> {
  late Timer _timer;
  Duration _remainingTime = Duration.zero;

  @override
  void initState() {
    super.initState();
    _remainingTime = widget.duration;
    _startTimer();
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _remainingTime = widget.duration - Duration(seconds: timer.tick);
        if (_remainingTime <= Duration.zero) {
          _timer.cancel();
          widget.onExamOver();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final hours = _remainingTime.inHours.remainder(24);
    final minutes = _remainingTime.inMinutes.remainder(60);
    final seconds = _remainingTime.inSeconds.remainder(60);
    Color? textColor;

    if (_remainingTime.inMinutes <= 5) {
      textColor = Colors.red;
    } else if (_remainingTime.inMinutes <= 10) {
      textColor = Colors.orange;
    } else if (_remainingTime.inMinutes <= 15) {
      textColor = Colors.yellow;
    }

    return Text(
      '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
      style:
          Theme.of(context).textTheme.headlineLarge?.copyWith(color: textColor),
    );
  }
}

class GradeMarkings extends StatelessWidget {
  final ExamSubject subject;

  const GradeMarkings({Key? key, required this.subject}) : super(key: key);

  Text _getGradeMarkingText(BuildContext context, int correctCount) {
    final chart = subject.gradeMarkings;
    final gradeMarking = chart.entries
        .firstWhere((entry) => correctCount >= entry.value,
            orElse: () => chart.entries.last)
        .key;
    final Color color;

    // https://cap.rcpet.edu.tw/score3.html
    if (subject.subjectId == CAPSubject.englishListening &&
        gradeMarking.contains('基礎')) {
      color = Colors.green;
    } else if (gradeMarking.contains('A') || gradeMarking.contains('精熟')) {
      color = Colors.green;
    } else if (gradeMarking.contains('B+') || gradeMarking.contains('基礎')) {
      color = Colors.blue;
    } else if (gradeMarking.contains('B')) {
      color = Colors.orange;
    } else if (gradeMarking.contains('C') || gradeMarking.contains('待加強')) {
      color = Colors.red;
    } else {
      color = Colors.white;
    }

    return Text(gradeMarking,
        style: Theme.of(context)
            .textTheme
            .displayMedium
            ?.copyWith(color: color, fontWeight: FontWeight.bold));
  }

  @override
  Widget build(BuildContext context) {
    final allQuestion = subject.getOptionalQuestions();
    final correctCount = allQuestion.where((q) => q.isCorrect).length;
    final textStyle = Theme.of(context).textTheme.bodyLarge;

    return Column(
      children: [
        Text('等級加標示', style: textStyle),
        _getGradeMarkingText(context, correctCount),
        Text('答對題數（$correctCount / ${allQuestion.length}）', style: textStyle),
        Text('記得看看詳解了解問題，加油！', style: textStyle),
      ],
    );
  }
}