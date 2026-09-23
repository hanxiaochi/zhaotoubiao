import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["maximum", "awarded", "feedback"]

  connect() { this.update() }

  update() {
    const maximum = Number(this.maximumTarget.value)
    const awarded = Number(this.awardedTarget.value)
    const valid = this.maximumTarget.value !== "" && this.awardedTarget.value !== "" &&
      Number.isFinite(maximum) && Number.isFinite(awarded) && maximum > 0 &&
      maximum <= 100 && awarded >= 0 && awarded <= maximum
    this.feedbackTarget.textContent = valid
      ? `本项得分比例 ${(awarded / maximum * 100).toFixed(1)}%，扣分 ${(maximum - awarded).toFixed(2)}。保存后由服务端汇总。`
      : "请输入有效分值：满分大于 0 且不超过 100，自评分在 0 至该项满分之间。"
  }
}
