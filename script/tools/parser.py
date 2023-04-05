import json
import re
from typing import Callable, NewType

import fitz
from fitz import Document, Page
from fitz.utils import get_text, search_for

from models.cap_subject import CAPSubject
from models.exam import Exam
from models.optional_question import QuestionChoice, QuestionAnswer
from models.single_choice_question import SingleChoiceQuestion
from models.subject_question import SubjectQuestion
from tools.pdf import parse_document_table

ANSWERS_TYPE = NewType("ANSWERS_TYPE", dict[CAPSubject, list[QuestionAnswer]])
EXAM_INDICATOR = NewType("EXAM_INDICATOR", dict[CAPSubject, float])


# TODO: Support image and table parsing
def parse_exam_paper(file_path: str, subject: CAPSubject, answers: ANSWERS_TYPE, passing_rates: EXAM_INDICATOR,
                     discrimination_indexes: EXAM_INDICATOR) -> list[SubjectQuestion]:
    """
    Parse the exam paper and return a list of exam result.
    Args:
        file_path (str): The exam paper file path.
        subject (CAPSubject): The exam subject.
        answers (ANSWERS_TYPE): The correct answers of the exam paper. Can be obtained by calling parse_exam_answer().
        passing_rates (EXAM_INDICATOR): The exam passing rates. Can be obtained by calling parse_exam_indicator().
        discrimination_indexes (EXAM_INDICATOR): The exam discrimination indexes.
            Can be obtained by calling parse_exam_indicator().

    Returns:
        list[SubjectQuestion]: A list of exam result.
    """
    doc = Document(file_path)
    pages: list[Page] = doc.pages()
    doc_text: str = ""
    result: list[SubjectQuestion] = []

    for page in pages:
        # Skip the CAP exam instructions page.
        if page.number == 0:
            continue

        doc_text += get_text(page, sort=True)

    matches = re.finditer(r"(\d+)\..*?(?=\d+\.|試題結束|請閱讀以下短文|第二部分:非選擇題)", doc_text, flags=re.DOTALL)

    filtered_questions: list[str] = []

    for match in matches:
        question_number = int(match.group(1))

        """
        Handle the case that the question has additional information.
        For example:
        Which idea is talked about in the first paragraph of the reading?
        (A) ...
         paragraph 段落 (This is additional information.)
        (B) ...
        (C) ...
        (D) ...
        """
        if len(filtered_questions) + 1 != question_number:
            filtered_questions[len(filtered_questions) - 1] += match.group(0)
        else:
            filtered_questions.append(match.group(0))

    for question in filtered_questions:
        choices_pattern = r"\([A-D]\)[^()]+"

        number = int(re.search(r"^\d+\.", question).group(0).replace(".", ""))
        choices: list[str] = re.findall(choices_pattern, question)
        description = fix_question_text(
            re.sub(choices_pattern, "", question).replace(str(number), "", 1).replace(".", "", 1))
        correct_answer = answers[subject][number - 1]
        passing_rate = passing_rates[subject][number - 1]
        discrimination_index = discrimination_indexes[subject][number - 1]

        parsed_choices: list[QuestionChoice] = []

        for choice in choices:
            choice_description = fix_question_text(re.sub(r"\([A-D]\)", "", choice))
            choice_answer = re.search(r"\([A-D]\)", choice).group(0).replace("(", "").replace(")", "")
            parsed_choices.append(
                QuestionChoice(choice_description if choice_description != "" else None, QuestionAnswer(choice_answer)))

        question = SingleChoiceQuestion(number, description, parsed_choices, correct_answer,
                                        passing_rate, discrimination_index)
        result.append(question)

    return result


def parse_tabular_file(file_path: str, sort_pattern: re.Pattern, convert_values_to_list: Callable[[str], list],
                       get_page_bottom: Callable[[Page], int], is_indicator: bool) -> \
        dict[CAPSubject, list[str]]:
    doc = Document(file_path)
    pages: list[Page] = list(doc.pages())
    year = int(re.search(r"(\d+)年|(\d+) 年", get_text(pages[0], sort=True)).group(0).replace("年", "").strip())
    sorted_table: list[str] = []
    result: dict[CAPSubject, list[str]] = {}

    # R.O.C 108 Curriculum Guidelines.
    new_curriculum_guidelines = year >= 111
    # Each subject has different question number range.
    english_listening_end = 21
    math_end = 26 if year in [106, 107, 108, 109, 110] else 25
    english_reading_end = 43 if new_curriculum_guidelines else (40 if year == 104 else 41)
    chinese_end = 43 if new_curriculum_guidelines else 48
    nature_end = 50 if new_curriculum_guidelines else 54

    # Initialize the result dict.
    for subject in CAPSubject:
        result[subject] = []

    for page in pages:
        table_top: fitz.Rect = search_for(page, "閱讀", hit_max=1)[0]

        table = parse_document_table(page, [0, table_top.y1, 99999, get_page_bottom(page)])
        # Flatten the table.
        table = [item for sublist in table for item in sublist]
        # Sort the table by the question number.
        for value_index, item in enumerate(table):
            question_number = (value_index if page.number == 0 else value_index + 30) + 1

            if question_number + 1 > nature_end:  # Only left society exam questions.
                sorted_table.append(item)
            elif len(item) == 1:
                sorted_table.append(item + table[value_index + 1])
            elif len(table[value_index - 1]) != 1:  # Skip the parsed question (see the if statement above).
                sorted_table.append(item)

    sorted_table = [re.sub(sort_pattern, "", item) for item in sorted_table]
    sorted_table = [item for item in sorted_table if item != ""]

    def handle_values(_values_list: list[str], _subjects: list[CAPSubject]):
        for i, _subject in enumerate(_subjects):
            result[_subject].append(_values_list[i])

    for index, values in enumerate(sorted_table):
        # R.O.C 108 Curriculum Guidelines.
        question_number = index + 1
        values_list = convert_values_to_list(values)

        # Handle question number range.
        if question_number <= english_listening_end:
            subjects = [subject for subject in CAPSubject]

            if is_indicator:
                subjects = [CAPSubject.CHINESE, CAPSubject.ENGLISH_LISTENING, CAPSubject.ENGLISH_Reading,
                            CAPSubject.MATH, CAPSubject.SOCIETY, CAPSubject.NATURE]

            # Due to the severity of the COVID-19 epidemic in ROC 109 (2020), the English listening exam was suspended.
            # See also: https://cap.rcpet.edu.tw/PressRelease1090422.html
            if year == 109:
                subjects.remove(CAPSubject.ENGLISH_LISTENING)

            handle_values(values_list, subjects)
        elif question_number <= math_end:
            subjects = [CAPSubject.CHINESE, CAPSubject.ENGLISH_Reading, CAPSubject.MATH, CAPSubject.SOCIETY,
                        CAPSubject.NATURE]
            handle_values(values_list, subjects)
        elif question_number <= english_reading_end:
            subjects = [CAPSubject.CHINESE, CAPSubject.ENGLISH_Reading, CAPSubject.SOCIETY, CAPSubject.NATURE]

            if new_curriculum_guidelines and question_number > 42:
                subjects.remove(CAPSubject.CHINESE)

            handle_values(values_list, subjects)
        elif question_number <= chinese_end:
            handle_values(values_list, [CAPSubject.CHINESE, CAPSubject.SOCIETY, CAPSubject.NATURE])
        elif question_number <= nature_end:
            handle_values(values_list, [CAPSubject.SOCIETY, CAPSubject.NATURE])
        else:
            handle_values(values_list, [CAPSubject.SOCIETY])

    return result


def parse_exam_answer(file_path: str) -> ANSWERS_TYPE:
    # Remove the question number and space.
    sort_pattern = re.compile(r"\d+| ")
    parsed_result = parse_tabular_file(file_path, sort_pattern, lambda x: list(x), lambda x: 99999, False)
    result: ANSWERS_TYPE = ANSWERS_TYPE({})

    for subject in parsed_result:
        result[subject] = [QuestionAnswer(answer) for answer in parsed_result[subject]]

    return result


def parse_exam_indicator(file_path: str) -> EXAM_INDICATOR:
    """
    Parse the exam indicator file.

    An indicator stands for the passing rate or discrimination index of the question.
    Args:
        file_path: The path of the exam indicator file.

    Returns:
        A dict with the subject as the key and the list of indicators as the value by the order of the question number.
    """
    sort_pattern = re.compile(r"^(\d+)(?:\.(\d{1,2}))?")
    result = EXAM_INDICATOR({})

    def convert_values_to_list(values: str) -> list:
        converted_values = []

        # Split the values by any whitespace.
        # For example, " 0.95 0.85 0.77 0.42 0.94" will be split into ["0.95", "0.85", "0.77", "0.42", "0.94"]
        for value in re.split(r"\s+", values):
            if value != "":
                converted_values.append(value)

        return converted_values

    def get_page_bottom(page: fitz.Page) -> int:
        found = search_for(page, "備註：", hit_max=1)

        if len(found) == 1:
            return found[0].y0
        else:
            return 99999

    parsed_result = parse_tabular_file(file_path, sort_pattern, convert_values_to_list, get_page_bottom, True)

    for subject in parsed_result:
        result[subject] = [float(value) for value in parsed_result[subject]]

    # final_result = EXAM_INDICATOR(result.copy())
    #
    # # Because the order of subjects in the indicator file is Chinese -> English Listening -> English Reading...
    # # The order of subjects is not the same as the answer file, so replace it here.
    # final_result[CAPSubject.ENGLISH_LISTENING] = result[CAPSubject.ENGLISH_Reading]
    # final_result[CAPSubject.ENGLISH_Reading] = result[CAPSubject.ENGLISH_LISTENING]

    return result


def save_parse_result(exams: list[Exam]):
    json_str = json.dumps([exam.to_dict() for exam in exams], ensure_ascii=False)
    with open("temp/cap_exams.json", "w") as f:
        f.write(json_str)


def fix_question_text(text: str) -> str:
    text = re.sub(r"(\w+)\n(\w+)", r"\1\2", text)
    text = re.sub(r"(\w+)\d\n請翻頁繼續作答", r"\1", text)
    text = re.sub(r" \n\d請翻頁繼續作答", r"", text)

    return text.strip()