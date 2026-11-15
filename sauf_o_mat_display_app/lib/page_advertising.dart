import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sauf_o_mat_display_app/backend_connection.dart';
import 'package:sauf_o_mat_display_app/theme.dart';
import 'package:sauf_o_mat_display_app/globals.dart';

class PageAdvertising extends StatelessWidget {
  const PageAdvertising({super.key});

  Future<Map> _fetchAdvertisingData() async {
    try {
      return await SalesforceService().getPageAdvertising();
    } catch (e) {
      debugPrint('Error fetching page 5 advertising image: $e');
      return {};
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map>(
      future: _fetchAdvertisingData(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting ||
            snapshot.hasError ||
            !snapshot.hasData ||
            snapshot.data!.isEmpty) {
          return Center(
            child: CircularProgressIndicator(color: defaultOnPrimary),
          );
        } else {
          SalesforceService().setPageAdvertisingVisualizedAt(
            snapshot.data!["id"],
            DateTime.now(),
          );
          final imageUrl = snapshot.data!["image"] ?? "";
          final imageWidth = MySize(context).w * 0.32;

          // Newspaper image is drawn at full screen width, keeping its aspect ratio.
          final paperWidth = MySize(context).w;
          final scale = paperWidth / _newspaperImageSize.width;
          final paperHeight = _newspaperImageSize.height * scale;
          final corners = _pageCorners.map((p) => p * scale).toList();
          final contentSize = Size(
            corners[1].dx - corners[0].dx,
            corners[3].dy - corners[0].dy,
          );

          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: paperWidth,
              height: paperHeight,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      'assets/newspaper.png',
                      fit: BoxFit.fill,
                    ),
                  ),
                  Transform(
                    transform: _quadTransform(contentSize, corners),
                    child: SizedBox.fromSize(
                      size: contentSize,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          contentSize.width * 0.06,
                          contentSize.height * 0.04,
                          contentSize.width * 0.06,
                          contentSize.height * 0.04,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              GlobalSettings.newspaperTitle,
                              style: NewspaperTextTheme.title.copyWith(
                                fontSize: 100,
                                height: 1.3,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            Padding(
                              padding: EdgeInsets.only(
                                bottom: MySize(context).h * 0.01,
                              ),
                              child: Divider(thickness: 4),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: MySize(context).w * 0.25,
                                  height: MySize(context).h * 0.6,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(20),
                                    child: Image.network(
                                      imageUrl,
                                      width: imageWidth,
                                      errorBuilder: (context, _, _) =>
                                          Container(
                                            width: imageWidth,
                                            height: imageWidth,
                                            color: Colors.grey[300],
                                            child: Icon(
                                              Icons.image,
                                              size: MySize(context).w * 0.3 / 2,
                                            ),
                                          ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      },
    );
  }
}

/// Pixel size of assets/newspaper.png.
const _newspaperImageSize = Size(1536, 1024);

/// Corners of the front page inside assets/newspaper.png (in image pixels),
/// in order: top-left, top-right, bottom-right, bottom-left.
/// Tweak these if the content doesn't sit exactly on the page.
const _pageCorners = [
  Offset(118, 60),
  Offset(1350, 36),
  Offset(1340, 956),
  Offset(97, 948),
];

/// Builds a perspective matrix that maps the rectangle (0,0)-[size] onto the
/// quadrilateral [quad] (top-left, top-right, bottom-right, bottom-left).
Matrix4 _quadTransform(Size size, List<Offset> quad) {
  final x0 = quad[0].dx, y0 = quad[0].dy;
  final x1 = quad[1].dx, y1 = quad[1].dy;
  final x2 = quad[2].dx, y2 = quad[2].dy;
  final x3 = quad[3].dx, y3 = quad[3].dy;

  final dx1 = x1 - x2, dx2 = x3 - x2, dx3 = x0 - x1 + x2 - x3;
  final dy1 = y1 - y2, dy2 = y3 - y2, dy3 = y0 - y1 + y2 - y3;

  final den = dx1 * dy2 - dx2 * dy1;
  final g = (dx3 * dy2 - dx2 * dy3) / den;
  final h = (dx1 * dy3 - dx3 * dy1) / den;

  // Unit square -> quad, then pre-scale so the input is in [size] coordinates.
  final a = (x1 - x0 + g * x1) / size.width;
  final b = (x3 - x0 + h * x3) / size.height;
  final d = (y1 - y0 + g * y1) / size.width;
  final e = (y3 - y0 + h * y3) / size.height;
  final gs = g / size.width;
  final hs = h / size.height;

  // Matrix4 is column-major.
  return Matrix4(
    a,
    d,
    0,
    gs, //
    b,
    e,
    0,
    hs, //
    0,
    0,
    1,
    0, //
    x0,
    y0,
    0,
    1, //
  );
}
