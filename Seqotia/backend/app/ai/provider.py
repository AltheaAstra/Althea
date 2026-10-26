from typing import Protocol


class SuggestionProvider(Protocol):
    name: str
    is_mock: bool

    def suggest(self, document_type: str, field_name: str, text: str) -> list[dict[str, str]]:
        """Return suggestions without accepting or applying them to a document."""


class DemoSuggestionProvider:
    name = "demo_mock"
    is_mock = True

    _examples = {
        "purpose": ["เพื่อสนับสนุนการดำเนินงานของหน่วยงาน", "เพื่อใช้ในงานตามวัตถุประสงค์ที่ระบุ"],
        "justification": ["เพื่อให้การดำเนินงานเป็นไปอย่างต่อเนื่อง", "โปรดระบุเหตุผลเพิ่มเติมตามความจำเป็นของงาน"],
        "issue_description": ["โปรดระบุอาการและช่วงเวลาที่เริ่มพบเพิ่มเติม", "โปรดตรวจสอบและบันทึกอาการที่พบตามจริง"],
        "notes": ["โปรดตรวจสอบรายละเอียดและเงื่อนไขก่อนยืนยัน", "ระบุข้อมูลอ้างอิงเพิ่มเติมเมื่อมี"],
        "default": ["โปรดตรวจสอบและแก้ไขข้อความให้ตรงกับข้อมูลจริงก่อนบันทึก"],
    }

    def suggest(self, document_type: str, field_name: str, text: str) -> list[dict[str, str]]:
        # The example provider deliberately does not turn user input into factual claims.
        values = self._examples.get(field_name, self._examples["default"])
        return [{"text": value, "style": "formal" if index == 0 else "concise"} for index, value in enumerate(values)]
