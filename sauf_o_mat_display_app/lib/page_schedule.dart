import 'package:flutter/material.dart';

class PageSchedule extends StatelessWidget {
  const PageSchedule({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: Container(
        decoration: BoxDecoration(
          //border: Border.all(color: Colors.black, width: 8),
        ),
        child: Image.asset("assets/timetable.png"),
      ),
    );
  }
}
