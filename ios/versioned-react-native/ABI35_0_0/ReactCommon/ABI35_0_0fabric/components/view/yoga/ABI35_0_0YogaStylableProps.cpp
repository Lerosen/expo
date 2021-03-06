/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#include "ABI35_0_0YogaStylableProps.h"

#include <ReactABI35_0_0/components/view/conversions.h>
#include <ReactABI35_0_0/components/view/propsConversions.h>
#include <ReactABI35_0_0/core/propsConversions.h>
#include <ReactABI35_0_0/debug/debugStringConvertibleUtils.h>
#include <ABI35_0_0yoga/ABI35_0_0YGNode.h>
#include <ABI35_0_0yoga/ABI35_0_0Yoga.h>

#include "ABI35_0_0conversions.h"

namespace facebook {
namespace ReactABI35_0_0 {

YogaStylableProps::YogaStylableProps(const ABI35_0_0YGStyle &ABI35_0_0yogaStyle)
    : ABI35_0_0yogaStyle(ABI35_0_0yogaStyle) {}

YogaStylableProps::YogaStylableProps(
    const YogaStylableProps &sourceProps,
    const RawProps &rawProps)
    : ABI35_0_0yogaStyle(convertRawProp(rawProps, sourceProps.ABI35_0_0yogaStyle)){};

#pragma mark - DebugStringConvertible

#if RN_DEBUG_STRING_CONVERTIBLE
SharedDebugStringConvertibleList YogaStylableProps::getDebugProps() const {
  auto defaultYogaStyle = ABI35_0_0YGStyle{};
  return {
      debugStringConvertibleItem(
          "direction", ABI35_0_0yogaStyle.direction, defaultYogaStyle.direction),
      debugStringConvertibleItem(
          "flexDirection",
          ABI35_0_0yogaStyle.flexDirection,
          defaultYogaStyle.flexDirection),
      debugStringConvertibleItem(
          "justifyContent",
          ABI35_0_0yogaStyle.justifyContent,
          defaultYogaStyle.justifyContent),
      debugStringConvertibleItem(
          "alignContent",
          ABI35_0_0yogaStyle.alignContent,
          defaultYogaStyle.alignContent),
      debugStringConvertibleItem(
          "alignItems", ABI35_0_0yogaStyle.alignItems, defaultYogaStyle.alignItems),
      debugStringConvertibleItem(
          "alignSelf", ABI35_0_0yogaStyle.alignSelf, defaultYogaStyle.alignSelf),
      debugStringConvertibleItem(
          "positionType",
          ABI35_0_0yogaStyle.positionType,
          defaultYogaStyle.positionType),
      debugStringConvertibleItem(
          "flexWrap", ABI35_0_0yogaStyle.flexWrap, defaultYogaStyle.flexWrap),
      debugStringConvertibleItem(
          "overflow", ABI35_0_0yogaStyle.overflow, defaultYogaStyle.overflow),
      debugStringConvertibleItem(
          "display", ABI35_0_0yogaStyle.display, defaultYogaStyle.display),
      debugStringConvertibleItem("flex", ABI35_0_0yogaStyle.flex, defaultYogaStyle.flex),
      debugStringConvertibleItem(
          "flexGrow", ABI35_0_0yogaStyle.flexGrow, defaultYogaStyle.flexGrow),
      debugStringConvertibleItem(
          "flexShrink", ABI35_0_0yogaStyle.flexShrink, defaultYogaStyle.flexShrink),
      debugStringConvertibleItem(
          "flexBasis", ABI35_0_0yogaStyle.flexBasis, defaultYogaStyle.flexBasis),
      debugStringConvertibleItem(
          "margin", ABI35_0_0yogaStyle.margin, defaultYogaStyle.margin),
      debugStringConvertibleItem(
          "position", ABI35_0_0yogaStyle.position, defaultYogaStyle.position),
      debugStringConvertibleItem(
          "padding", ABI35_0_0yogaStyle.padding, defaultYogaStyle.padding),
      debugStringConvertibleItem(
          "border", ABI35_0_0yogaStyle.border, defaultYogaStyle.border),
      debugStringConvertibleItem(
          "dimensions", ABI35_0_0yogaStyle.dimensions, defaultYogaStyle.dimensions),
      debugStringConvertibleItem(
          "minDimensions",
          ABI35_0_0yogaStyle.minDimensions,
          defaultYogaStyle.minDimensions),
      debugStringConvertibleItem(
          "maxDimensions",
          ABI35_0_0yogaStyle.maxDimensions,
          defaultYogaStyle.maxDimensions),
      debugStringConvertibleItem(
          "aspectRatio", ABI35_0_0yogaStyle.aspectRatio, defaultYogaStyle.aspectRatio),
  };
}
#endif

} // namespace ReactABI35_0_0
} // namespace facebook
