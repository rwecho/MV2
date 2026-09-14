# Logo 重设计探索

原意：**黑客帝国的红药丸 / 蓝药丸 = V 的两边，中间站着一个正在做选择的人。**
现在的成品（`../mv2_logo.svg`）是渐变的 V + 底部一个点，这个意思没表达出来。

## 为什么原版读不出原意

1. **渐变（紫→粉 / 蓝→粉）不是"红药丸 / 蓝药丸"**，把药丸的物体感稀释成了装饰线条。
2. **底部的点是句号，不是人**：太小、和 V 的顶点只是相邻，没有"人站在岔路口"的结构。
3. **两条边太长（长宽比 ≈5:1）**，读起来是线段而不是胶囊药丸。

## 两条工艺规则（本轮据此重画）

- **药丸长宽比 ≈2.5:1**，圆头，加一道接缝（seam）才读得出是胶囊。
- **人必须与药丸留出明确间隙**，否则缩小后糊成一个深色团块；人要比第一版明显放大。

## 候选

| 代号 | 文件 | 说明 |
|---|---|---|
| A | `a_capsule_v_person.svg` | 直杆双色 + 人（第一版） |
| B | `b_capsule_v_person_seam.svg` | A + 接缝 |
| C | `c_curved_v_person.svg` | 保留原曲线，只换色 + 换成人形 |
| D | `d_person_two_pills.svg` | 不做 V，人居中两丸分列 |
| E | `e_pills_v_person.svg` | 药丸比例修正 + 人独立（第二版） |
| F | `f_pills_v_person_seam.svg` | E + 接缝 |
| G | `g_person_flanked_pills.svg` | 不做 V，药丸斜向人 |
| **H** | `h_pills_v_person_large.svg` | **推荐**：F 基础上放大人物、药丸略收窄 |

## 复现

```bash
python3 app/branding/explorations/build_sheet.py              # 两轮对比图
python3 app/branding/explorations/build_legibility_strip.py   # 小尺寸实检条
```

产出：`contact_sheet.png`、`contact_sheet_v2.png`、`legibility_strip.png`。

## 待定

- 采用哪个方向（推荐 H）。
- 人物配色：近黑剪影（当前）／品牌靛蓝／白色挖空。
- 红色取值：Matrix 感 `#E5484D`（当前）或更暗的 `#D92D20`。
- 是否要保留 V 字形（V2EX 联想）。
