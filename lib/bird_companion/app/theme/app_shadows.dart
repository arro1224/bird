import 'package:flutter/material.dart';

abstract final class AppShadows {
  static const card = <BoxShadow>[
    BoxShadow(
      color: Color(0x120F2E1A),
      blurRadius: 20,
      offset: Offset(0, 6),
    ),
  ];

  static const floating = <BoxShadow>[
    BoxShadow(
      color: Color(0x1A0F2E1A),
      blurRadius: 28,
      offset: Offset(0, 10),
    ),
  ];

  static const navigation = <BoxShadow>[
    BoxShadow(
      color: Color(0x0F0F2E1A),
      blurRadius: 18,
      offset: Offset(0, -4),
    ),
  ];

  static const darkCard = <BoxShadow>[
    BoxShadow(
      color: Color(0x52000000),
      blurRadius: 18,
      offset: Offset(0, 6),
    ),
  ];

  static List<BoxShadow> cardFor(Brightness brightness) => brightness == Brightness.light ? card : darkCard;
}
